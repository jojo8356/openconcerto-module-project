package org.openconcerto.modules.project;

import java.io.BufferedOutputStream;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.sql.SQLException;
import java.text.DateFormat;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import javax.swing.JFileChooser;

import org.openconcerto.sql.model.DBRoot;
import org.openconcerto.sql.model.SQLRow;
import org.openconcerto.sql.model.SQLRowListRSH;
import org.openconcerto.sql.model.SQLRowValues;
import org.openconcerto.sql.model.SQLRowValuesListFetcher;
import org.openconcerto.sql.model.SQLSelect;
import org.openconcerto.sql.model.SQLTable;
import org.openconcerto.utils.StringUtils;

public class ProjectImportExport {

    private final DBRoot root;

    public ProjectImportExport(DBRoot root) {
        this.root = root;
    }

    public File export() {
        File exportedFile = null;
        JFileChooser chooser = new JFileChooser();
        chooser.setFileSelectionMode(JFileChooser.DIRECTORIES_ONLY);
        if (chooser.showDialog(null, null) == JFileChooser.APPROVE_OPTION) {
            exportedFile = new File(chooser.getSelectedFile(), "exportedProjects.txt");
            final SQLTable affaireTable = this.root.findTable("AFFAIRE");
            SQLRowValues rowVals = new SQLRowValues(affaireTable);
            rowVals.putNulls(affaireTable.getFieldsName());

            final SQLTable commandeFTable = this.root.getTable("COMMANDE");
            SQLRowValues rowValsCommandeF = new SQLRowValues(commandeFTable);
            rowValsCommandeF.putNulls("NUMERO");
            rowValsCommandeF.put("ID_AFFAIRE", rowVals);

            final SQLTable devisTable = this.root.getTable("DEVIS");
            SQLRowValues rowValsDevis = new SQLRowValues(devisTable);
            rowValsDevis.putNulls("NUMERO");
            rowValsDevis.put("ID_AFFAIRE", rowVals);

            final SQLTable avoirTable = this.root.getTable("AVOIR_CLIENT");
            SQLRowValues rowValsAvoir = new SQLRowValues(avoirTable);
            rowValsAvoir.putNulls("NUMERO");
            rowValsAvoir.put("ID_AFFAIRE", rowVals);

            final SQLTable cmdTable = this.root.getTable("COMMANDE_CLIENT");
            SQLRowValues rowValsCmd = new SQLRowValues(cmdTable);
            rowValsCmd.putNulls("NUMERO");
            rowValsCmd.put("ID_AFFAIRE", rowVals);

            final SQLTable blTable = this.root.getTable("BON_DE_LIVRAISON");
            SQLRowValues rowValsBL = new SQLRowValues(blTable);
            rowValsBL.putNulls("NUMERO");
            rowValsBL.put("ID_AFFAIRE", rowVals);

            final SQLTable factTable = this.root.getTable("SAISIE_VENTE_FACTURE");
            SQLRowValues rowValsFact = new SQLRowValues(factTable);
            rowValsFact.putNulls("NUMERO");
            rowValsFact.put("ID_AFFAIRE", rowVals);

            List<SQLRowValues> results = SQLRowValuesListFetcher.create(rowVals).fetch();
            BufferedOutputStream stream = null;
            try {
                stream = new BufferedOutputStream(new FileOutputStream(exportedFile));
                for (SQLRowValues sqlRowValues : results) {
                    if (sqlRowValues.getDate("DATE") != null) {
                        StringBuffer buf = new StringBuffer();
                        buf.append(sqlRowValues.getString("NUMERO"));
                        buf.append("\t");
                        buf.append(sqlRowValues.getString("INFOS"));
                        buf.append("\t");
                        buf.append(sqlRowValues.getInt("ID_CLIENT"));
                        buf.append("\t");
                        DateFormat format = new SimpleDateFormat("dd MM yyyy");
                        buf.append(format.format(sqlRowValues.getDate("DATE").getTime()));
                        buf.append("\t");
                        buf.append(sqlRowValues.getInt("ID_COMMERCIAL"));
                        buf.append("\t");
                        buf.append(sqlRowValues.getInt("ID_ETAT_AFFAIRE"));
                        buf.append("\t");
                        buf.append(sqlRowValues.getInt("ID_DEVIS"));
                        buf.append("\t");

                        List<String> devis = new ArrayList<String>();
                        Collection<SQLRowValues> devisRows = sqlRowValues.getReferentRows(devisTable);
                        for (SQLRowValues sqlRowValuesDevis : devisRows) {
                            devis.add(sqlRowValuesDevis.getString("NUMERO"));
                        }
                        buf.append(devis.toString());
                        buf.append("\t");

                        List<String> commandes = new ArrayList<String>();
                        Collection<SQLRowValues> commandesRows = sqlRowValues.getReferentRows(commandeFTable);
                        for (SQLRowValues sqlRowValuesCommande : commandesRows) {
                            commandes.add(sqlRowValuesCommande.getString("NUMERO"));
                        }
                        buf.append(commandes.toString());
                        buf.append("\t");

                        List<String> avoirs = new ArrayList<String>();
                        Collection<SQLRowValues> avoirsRows = sqlRowValues.getReferentRows(avoirTable);
                        for (SQLRowValues sqlRowValuesAvoir : avoirsRows) {
                            avoirs.add(sqlRowValuesAvoir.getString("NUMERO"));
                        }
                        buf.append(avoirs.toString());
                        buf.append("\t");

                        List<String> bls = new ArrayList<String>();
                        Collection<SQLRowValues> blRows = sqlRowValues.getReferentRows(blTable);
                        for (SQLRowValues sqlRowValuesBL : blRows) {
                            bls.add(sqlRowValuesBL.getString("NUMERO"));
                        }
                        buf.append(bls.toString());
                        buf.append("\t");

                        List<String> cmdClients = new ArrayList<String>();
                        Collection<SQLRowValues> cmdCliRows = sqlRowValues.getReferentRows(cmdTable);
                        for (SQLRowValues sqlRowValuesCmd : cmdCliRows) {
                            cmdClients.add(sqlRowValuesCmd.getString("NUMERO"));
                        }
                        buf.append(cmdClients.toString());
                        buf.append("\t");

                        List<String> facts = new ArrayList<String>();
                        Collection<SQLRowValues> factRows = sqlRowValues.getReferentRows(factTable);
                        for (SQLRowValues sqlRowValuesFact : factRows) {
                            facts.add(sqlRowValuesFact.getString("NUMERO"));
                        }
                        buf.append(facts.toString());
                        buf.append("\t\n");
                        stream.write(buf.toString().getBytes());
                    }
                }
            } catch (FileNotFoundException e) {
                // TODO Auto-generated catch block
                e.printStackTrace();
            } catch (IOException e) {
                // TODO Auto-generated catch block
                e.printStackTrace();
            } finally {
                if (stream != null) {
                    try {
                        stream.close();
                    } catch (IOException e) {
                        // TODO Auto-generated catch block
                        e.printStackTrace();
                    }
                }
            }
        }
        return exportedFile;

    }

    public void importProjects() {
        File importFile = null;
        JFileChooser chooser = new JFileChooser();
        chooser.setFileSelectionMode(JFileChooser.FILES_ONLY);
        if (chooser.showDialog(null, null) == JFileChooser.APPROVE_OPTION) {
            importFile = chooser.getSelectedFile();
            final SQLTable affaireTable = this.root.findTable("AFFAIRE");
            SQLSelect sel = new SQLSelect();
            sel.addSelectStar(affaireTable);
            List<SQLRow> re = SQLRowListRSH.execute(sel);
            List<String> numbersAff = new ArrayList<String>();
            for (SQLRow sqlRow : re) {
                numbersAff.add(sqlRow.getString("NUMERO"));
            }
            BufferedReader stream = null;
            try {
                stream = new BufferedReader(new InputStreamReader(new FileInputStream(importFile)));

                String line = null;

                while ((line = stream.readLine()) != null) {
                    List<String> values = StringUtils.fastSplitTrimmed(line, '\t');
                    SQLRowValues rowValsAffaire = new SQLRowValues(affaireTable);
                    final String number = values.get(0);
                    if (!numbersAff.contains(number)) {
                        rowValsAffaire.put("NUMERO", number);

                        rowValsAffaire.put("INFOS", values.get(1));
                        rowValsAffaire.put("ID_CLIENT", Integer.valueOf(values.get(2)));
                        DateFormat format = new SimpleDateFormat("dd MM yyyy");
                        rowValsAffaire.put("DATE", format.parse(values.get(3)));
                        rowValsAffaire.put("ID_COMMERCIAL", Integer.valueOf(values.get(4)));
                        rowValsAffaire.put("ID_ETAT_AFFAIRE", Integer.valueOf(values.get(5)));
                        rowValsAffaire.put("ID_DEVIS", Integer.valueOf(values.get(6)));

                        int id = rowValsAffaire.commit().getID();

                        final String stringDevis = values.get(7);
                        List<String> devis = Arrays.asList(stringDevis.substring(1, stringDevis.length() - 1).split("\\s*,\\s*"));
                        link(devis, id, affaireTable.getTable("DEVIS"));

                        final String stringCommandes = values.get(8);
                        List<String> cmds = Arrays.asList(stringCommandes.substring(1, stringCommandes.length() - 1).split("\\s*,\\s*"));
                        link(cmds, id, affaireTable.getTable("COMMANDE"));

                        final String stringAvoirs = values.get(9);
                        List<String> avoirs = Arrays.asList(stringAvoirs.substring(1, stringAvoirs.length() - 1).split("\\s*,\\s*"));
                        link(avoirs, id, affaireTable.getTable("AVOIR_CLIENT"));

                        final String stringBls = values.get(10);
                        List<String> bls = Arrays.asList(stringBls.substring(1, stringBls.length() - 1).split("\\s*,\\s*"));
                        link(bls, id, affaireTable.getTable("BON_DE_LIVRAISON"));

                        final String stringCmdClis = values.get(11);
                        List<String> cmdClis = Arrays.asList(stringCmdClis.substring(1, stringCmdClis.length() - 1).split("\\s*,\\s*"));
                        link(cmdClis, id, affaireTable.getTable("COMMANDE_CLIENT"));

                        final String stringVFs = values.get(12);
                        List<String> vfs = Arrays.asList(stringVFs.substring(1, stringVFs.length() - 1).split("\\s*,\\s*"));
                        link(vfs, id, affaireTable.getTable("SAISIE_VENTE_FACTURE"));
                    }
                }
            } catch (NumberFormatException e) {
                // TODO Auto-generated catch block
                e.printStackTrace();
            } catch (IOException e) {
                // TODO Auto-generated catch block
                e.printStackTrace();
            } catch (ParseException e) {
                // TODO Auto-generated catch block
                e.printStackTrace();
            } catch (SQLException e) {
                // TODO Auto-generated catch block
                e.printStackTrace();
            }
        }

    }

    Map<SQLTable, Map<String, SQLRow>> cache = new HashMap<SQLTable, Map<String, SQLRow>>();

    private void link(List<String> number, int id, SQLTable table) throws SQLException {

        Map<String, SQLRow> linkMap = cache.get(table);

        if (linkMap == null) {
            linkMap = new HashMap<String, SQLRow>();
            cache.put(table, linkMap);
            SQLSelect sel = new SQLSelect();
            sel.addSelect(table.getKey());
            sel.addSelect(table.getField("NUMERO"));

            List<SQLRow> rows = SQLRowListRSH.execute(sel);
            for (SQLRow sqlRow : rows) {
                linkMap.put(sqlRow.getString("NUMERO"), sqlRow);
            }
        }

        for (String string : number) {
            if (string.trim().length() > 0) {
                if (linkMap.containsKey(string)) {
                    linkMap.get(string).createEmptyUpdateRow().put("ID_AFFAIRE", id).commit();
                } else {
                    System.err.println(table.getName() + " NUMERO " + string + " NOT FOUND!!!!!!!!!");
                }
            }
        }

    }

}
