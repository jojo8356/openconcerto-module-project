#!/usr/bin/env python3
"""Injecte un fichier preseed.cfg a la racine d'un initrd Debian (cpio newc).

Pourquoi
--------
La methode « network preseeding » (preseed/url=...) n'est lue par
l'installateur qu'APRÈS la configuration reseau, et elle echoue completement
si le fichier n'est pas telecharge (c'est ce qui se produisait : l'installateur
installait le bureau au lieu de la tache « ssh-server »).

La methode officielle « initrd preseeding » est, elle, lue des la premiere
question : il suffit que le fichier se nomme preseed.cfg et qu'il soit place a
la racine de l'initramfs.

Ce script :
  1. decompresse l'initrd (gzip) ;
  2. relit l'archive cpio « newc » entry par entry ;
  3. ajoute /preseed.cfg (mode 0644) a la racine ;
  4. recompresse le tout dans un nouvel initrd.

Aucun droit administrateur, aucun outil externe : uniquement python3.

Utilisation :
    python3 inject-preseed-initrd.py initrd.gz preseed.cfg sortie.gz
"""

import gzip
import sys
import zlib

MAGIC = b"070701"
TRAILER = b"TRAILER!!!"


def decompress(data):
    """Renvoie (contenu decompresse, octets restants apres le flux)."""
    for wbits in (16 + zlib.MAX_WBITS, zlib.MAX_WBITS):
        try:
            obj = zlib.decompressobj(wbits)
            out = obj.decompress(data)
            out += obj.flush()
            return out, obj.unused_data
        except zlib.error:
            continue
    return None, b""


def parse_cpio(data):
    """Decoupe une archive cpio newc : renvoie la liste des entrees."""
    entries = []
    pos = 0
    total = len(data)
    while pos + 110 <= total:
        if data[pos:pos + 6] != MAGIC:
            break
        try:
            fields = [
                int(data[pos + 6 + i * 8:pos + 14 + i * 8], 16) for i in range(13)
            ]
        except ValueError:
            break
        filesize = fields[6]
        namesize = fields[11]
        name_start = pos + 110
        name = data[name_start:name_start + namesize - 1]
        dstart = name_start + namesize
        dstart += (-dstart) % 4
        body = data[dstart:dstart + filesize]
        end = dstart + filesize
        end += (-end) % 4
        entries.append((fields, name, body))
        pos = end
        if name == TRAILER:
            break
    return entries


def emit(entries):
    """Reecrit une archive cpio newc a partir des entrees."""
    out = bytearray()
    ino = 1
    for fields, name, body in entries:
        f = list(fields)
        f[0] = ino             # c_ino
        f[6] = len(body)       # c_filesize
        f[11] = len(name) + 1  # c_namesize
        f[12] = 0              # c_check
        ino += 1
        out += MAGIC
        for value in f:
            out += ("%08X" % (value & 0xFFFFFFFF)).encode()
        out += name + b"\0"
        out += b"\0" * ((-len(out)) % 4)
        out += body
        out += b"\0" * ((-len(out)) % 4)
    return bytes(out)


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)

    src, preseed_path, dst = sys.argv[1], sys.argv[2], sys.argv[3]

    raw = open(src, "rb").read()
    plain, tail = decompress(raw)
    if plain is None:
        sys.exit("initrd illisible (flux ni gzip ni zlib) : %s" % src)

    entries = parse_cpio(plain)
    if not entries:
        sys.exit("archive cpio newc non reconnue dans %s" % src)

    # Le marqueur de fin (TRAILER) ne doit pas rester : on le remet a la fin.
    entries = [e for e in entries if e[1] != TRAILER]

    # Un eventuel « early cpio » (microcode) place apres le flux gzip est
    # fusionne s'il est lisible, conserve tel quel sinon.
    if tail:
        extra = [e for e in parse_cpio(tail) if e[1] != TRAILER]
        if extra:
            entries.extend(extra)
            tail = b""

    content = open(preseed_path, "rb").read()

    # On remplace un eventuel preseed.cfg deja present.
    entries = [e for e in entries if e[1] != b"preseed.cfg"]
    entries.append(
        ([0, 0o100644, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0], b"preseed.cfg", content)
    )
    entries.append(
        ([0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0], TRAILER, b"")
    )

    archive = emit(entries)
    blob = gzip.compress(archive, 6)
    if tail and not parse_cpio(tail):
        blob += tail

    with open(dst, "wb") as handle:
        handle.write(blob)

    # Verification : on relit ce qu'on vient d'ecrire.
    check, _ = decompress(open(dst, "rb").read())
    names = [name for _, name, _ in parse_cpio(check)]
    if b"preseed.cfg" not in names:
        sys.exit("ECHEC : preseed.cfg absent de l'initrd produit")
    found = [body for _, name, body in parse_cpio(check) if name == b"preseed.cfg"][0]
    if found != content:
        sys.exit("ECHEC : contenu du preseed altere")
    print("preseed injecte dans l'initrd : %d entrees, %d octets (preseed %d o)"
          % (len(names), len(blob), len(content)))


if __name__ == "__main__":
    main()
