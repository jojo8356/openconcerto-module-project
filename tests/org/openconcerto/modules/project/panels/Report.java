package org.openconcerto.modules.project.panels;

import java.util.ArrayList;
import java.util.List;

/**
 * Resultat des controles : un compte rendu par niveau, et un code de sortie
 * different de zero si au moins un controle a echoue.
 */
public class Report {

    public static final int OK = 0;
    public static final int INFO = 1;
    public static final int WARN = 2;
    public static final int FAIL = 3;

    private final List<String> lines = new ArrayList<String>();
    private int ok;
    private int info;
    private int warn;
    private int fail;

    public void add(int level, String scope, String message) {
        final String prefix;
        if (level == FAIL) {
            prefix = "ECHEC  ";
            fail++;
        } else if (level == WARN) {
            prefix = "ALERTE ";
            warn++;
        } else if (level == INFO) {
            prefix = "INFO   ";
            info++;
        } else {
            prefix = "OK     ";
            ok++;
        }
        this.lines.add(prefix + "[" + scope + "] " + message);
    }

    public void ok(String scope, String message) {
        add(OK, scope, message);
    }

    public void info(String scope, String message) {
        add(INFO, scope, message);
    }

    public void warn(String scope, String message) {
        add(WARN, scope, message);
    }

    public void fail(String scope, String message) {
        add(FAIL, scope, message);
    }

    public int getFailures() {
        return this.fail;
    }

    public int getWarnings() {
        return this.warn;
    }

    public int getInfos() {
        return this.info;
    }

    public int getChecks() {
        return this.ok + this.info + this.warn + this.fail;
    }

    public List<String> getLines() {
        return this.lines;
    }

    public void print(java.io.PrintStream out) {
        for (int i = 0; i < this.lines.size(); i++) {
            out.println(this.lines.get(i));
        }
        out.println();
        out.println("Contrôles : " + this.getChecks() + " au total | " + this.ok + " OK | " + this.info + " info | " + this.warn + " alertes | " + this.fail + " echecs");
    }
}
