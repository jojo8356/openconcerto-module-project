package org.openconcerto.modules.project.panel;

import java.awt.GridBagConstraints;
import java.awt.GridBagLayout;
import java.awt.Insets;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.text.DecimalFormat;
import java.util.Collection;

import javax.swing.JLabel;
import javax.swing.JPanel;
import javax.swing.SwingConstants;
import javax.swing.SwingUtilities;

import org.openconcerto.erp.modules.ModuleFactory;
import org.openconcerto.sql.model.SQLRowAccessor;
import org.openconcerto.sql.model.SQLRowValues;
import org.openconcerto.sql.view.list.IListe;
import org.openconcerto.sql.view.list.ITableModel;
import org.openconcerto.ui.DefaultGridBagConstraints;
import org.openconcerto.utils.GestionDevise;

public class HistoriqueAffaireBilanPanel extends JPanel {

    private DecimalFormat decimalFormat = new DecimalFormat("0.00");

    private double pourcentCommande = 0;
    private final JLabel labelPourcentCommande = new JLabel("", SwingConstants.RIGHT);

    private long montantCommandeClient = 0;
    private final JLabel labelCommandeClient = new JLabel("", SwingConstants.RIGHT);

    private long montantBudget = 0;
    private final JLabel labelBudget = new JLabel("", SwingConstants.RIGHT);

    private long montantCommande = 0;
    private final JLabel labelCommande = new JLabel("", SwingConstants.RIGHT);

    private long montantCommandeP = 0;
    private final JLabel labelCommandeP = new JLabel("", SwingConstants.RIGHT);

    private long montantFacturer = 0;
    private final JLabel labelFacturer = new JLabel("", SwingConstants.RIGHT);

    private long montantRegler = 0;
    private final JLabel labelMontantRegler = new JLabel("", SwingConstants.RIGHT);

    private long montantRemise = 0;

    private long montantRestantFacturer = 0;
    private final JLabel labelRestantFacturer = new JLabel("", SwingConstants.RIGHT);

    private final JLabel labelAvoir = new JLabel("");
    private String motifAvoir = "";

    private long montantAchat = 0;
    private final JLabel labelAchat = new JLabel("", SwingConstants.RIGHT);

    private final JLabel labelPercentBilan = new JLabel("", SwingConstants.RIGHT);

    private final JLabel labelPercentMargeHT = new JLabel("", SwingConstants.RIGHT);

    private final JLabel labelPercentMBBilan = new JLabel("", SwingConstants.RIGHT);

    private final JLabel labelPercentMBAchat = new JLabel("", SwingConstants.RIGHT);

    private static ModuleFactory factory;

    public HistoriqueAffaireBilanPanel() {
        super();

        setLayout(new GridBagLayout());
        GridBagConstraints c = new DefaultGridBagConstraints();
        c.insets = new Insets(2, 2, 2, 75);
        c.gridx = GridBagConstraints.RELATIVE;
        c.gridy++;
        c.gridwidth = GridBagConstraints.REMAINDER;
        add(this.labelAvoir, c);

        c.gridy++;
        c.gridwidth = 1;
        add(this.labelCommandeClient, c);
        // add(this.labelCommandeP, c);
        add(this.labelPercentMargeHT, c);
        add(this.labelFacturer, c);

        c.gridy++;
        // add(this.labelPourcentCommande, c);
        add(this.labelBudget, c);
        add(this.labelCommande, c);
        add(this.labelPercentMBBilan, c);
        // add(this.labelMontantRegler, c);

        c.gridy++;
        // add(this.labelPercentBilan, c);
        // add(this.labelPourcentCommande, c);
        add(this.labelRestantFacturer, c);
        add(this.labelAchat, c);
        add(this.labelPercentMBAchat, c);

        // add(this.labelDemande);
        //
        // add(this.labelDemandeM);
        //
        // add(this.labelDemandeT);
        //
        // add(this.labelCommande);
        //
        // add(this.labelCommandeMonteur);
        //
        // add(this.labelCommandeTransporteur);
    }

    public synchronized void updateBilanPreBilan(final IListe listeCmdF) {
        // if (rowAffaire == null || rowAffaire.isUndefined()) {
        // this.montantCommande = 0;
        // this.montantCommandeP = 0;
        // return;
        // }
        long montant = 0;

        if (listeCmdF != null) {
            // Commande F
            for (int i = 0; i < listeCmdF.getRowCount(); i++) {
                final SQLRowValues rowAt = ITableModel.getLine(listeCmdF.getModel(), i).getRow();
                if (rowAt.getTable().getName().equalsIgnoreCase("COMMANDE_ELEMENT")) {
                    montant += rowAt.getBigDecimal("T_PA_HT").movePointRight(2).setScale(0, RoundingMode.HALF_UP).longValue();
                } else {
                    montant += rowAt.getLong("T_HT");
                }
            }
        }

        this.montantCommande = montant;

        updateLabels();
    }

    public synchronized void updateFacturer(final IListe liste, final IListe listeAvoir) {
        // List<SQLRowAccessor> rows =
        // liste.getSource().getLine(viewIndex)SelectedRows()Model().get;
        if (liste == null || listeAvoir == null) {
            return;
        }

        String motif = "";
        long montant = 0;
        BigDecimal montantRegler = BigDecimal.ZERO;
        long montantRemise = 0;
        for (int i = 0; i < liste.getRowCount(); i++) {
            final SQLRowValues rowAt = ITableModel.getLine(liste.getModel(), i).getRow();
            long ht = rowAt.getLong("T_HT");
            long ttc = rowAt.getLong("T_TTC");
            montant += ht;

            // BigDecimal regler = new
            // BigDecimal(calc.getReglement(rowAt.getForeign("ID_MOUVEMENT").getInt("ID_PIECE"),
            // null));
            // if (ht != ttc) {
            // if (rowAt.getDate("DATE").getTime().compareTo(date2014) <= 0) {
            // regler = regler.divide(new BigDecimal(1.196D), MathContext.DECIMAL128);
            // } else {
            // regler = regler.divide(new BigDecimal(1.2D), MathContext.DECIMAL128);
            // }
            // // regler = regler.divide(new BigDecimal(1.2D), MathContext.DECIMAL128);
            // }
            // montantRegler = montantRegler.add(regler);

        }

        // EncoursCalculator calc = new EncoursCalculator();
        for (int i = 0; i < listeAvoir.getRowCount(); i++) {
            final SQLRowValues rowAt = ITableModel.getLine(listeAvoir.getModel(), i).getRow();
            if (rowAt.getBoolean("A_DEDUIRE")) {
                montant -= rowAt.getLong("MONTANT_HT");
                // montantRegler -= rowAt.getLong("MONTANT_TTC");
            }
            // else {
            // long long1 = calc.getMontantAvoir(rowAt);
            // montant -= long1;
            // montantRemise += long1;
            // motif += rowAt.getString("MOTIF") + "(-" + GestionDevise.currencyToString(long1,
            // true) + " €)";
            // }
        }
        this.motifAvoir = motif;
        this.montantFacturer = montant;
        this.montantRemise = montantRemise;
        this.montantRegler = montantRegler.setScale(0, RoundingMode.HALF_UP).longValue();
        updateLabels();
    }

    public synchronized void updateAchat(final IListe listeAchat, final IListe listeAchatAvoir, final IListe listeFactureF, final IListe listeFactureFitem) {
        if (listeAchat == null) {
            return;
        }
        final ITableModel model = listeAchat.getModel();
        final ITableModel modelF = listeFactureF == null ? null : listeFactureF.getModel();
        final ITableModel modelFitem = listeFactureFitem == null ? null : listeFactureFitem.getModel();
        final ITableModel modelAvoir = listeAchatAvoir.getModel();
        final Runnable r = new Runnable() {
            @Override
            public void run() {
                long m = 0;
                for (int i = 0; i < model.getRowCount(); i++) {
                    final SQLRowValues rowAt = model.getRow(i).getRow();
                    m += rowAt.getLong("MONTANT_HT");
                }

                if (modelF != null) {
                    for (int i = 0; i < modelF.getRowCount(); i++) {
                        final SQLRowValues rowAt = modelF.getRow(i).getRow();
                        m += rowAt.getLong("T_HT");
                    }
                }

                if (modelFitem != null) {
                    for (int i = 0; i < modelFitem.getRowCount(); i++) {
                        final SQLRowValues rowAt = modelFitem.getRow(i).getRow();
                        m += rowAt.getBigDecimal("T_PA_HT").movePointRight(2).setScale(0, RoundingMode.HALF_UP).longValue();
                    }
                }

                for (int i = 0; i < modelAvoir.getRowCount(); i++) {
                    final SQLRowValues rowAt = modelAvoir.getRow(i).getRow();
                    m -= rowAt.getLong("MONTANT_HT");
                }
                montantAchat = m;

                SwingUtilities.invokeLater(new Runnable() {
                    @Override
                    public void run() {
                        updateLabels();
                    }
                });
            }
        };
        model.invokeLater(r);
        modelAvoir.invokeLater(r);

    }

    public synchronized void updateCommandeClient(SQLRowAccessor rowAff) {
        if (rowAff != null) {
            Collection<? extends SQLRowAccessor> rowCmd = rowAff.getReferentRows(rowAff.getTable().getTable("COMMANDE_CLIENT"));
            long cmd = 0;
            long b = 0;
            for (SQLRowAccessor r : rowCmd) {
                cmd += r.getLong("T_HT");
                Collection<? extends SQLRowAccessor> ref = r.getReferentRows(rowAff.getTable().getTable("CHIFFRAGE_COMMANDE_CLIENT"));
                for (SQLRowAccessor sqlRowAccessor : ref) {
                    b += sqlRowAccessor.getBigDecimal("T_PA_HT").setScale(0, RoundingMode.HALF_UP).longValue();
                }
            }

            this.montantBudget = b;
            this.montantCommandeClient = cmd;
            updateLabels();
        }
    }

    public synchronized void updateDevis(SQLRowAccessor rowAff) {
        if (rowAff != null) {
            Collection<? extends SQLRowAccessor> rowCmd = rowAff.getReferentRows(rowAff.getTable().getTable("DEVIS"));
            long cmd = 0;
            for (SQLRowAccessor r : rowCmd) {
                cmd += r.getLong("T_HA");
            }
            // this.montantBudget = cmd;
            updateLabels();
        }
    }

    private void updateLabels() {
        long mbP = this.montantCommandeClient - this.montantCommandeP;
        final long mbB = this.montantCommandeClient - this.montantCommande;
        long mbA = this.montantFacturer - this.montantAchat;

        final double percentMBPreBilan = Math.round((this.montantCommandeClient == 0 ? 0 : (double) mbP / (double) this.montantCommandeClient) * 10000.0D) / 100.0D;
        final double percentMBBilan = Math.round((this.montantCommandeClient == 0 ? 0 : (double) mbB / (double) this.montantCommandeClient) * 10000.0D) / 100.0D;
        final double percentMBAchat = Math.round((this.montantFacturer == 0 || this.montantAchat == 0 ? 0 : (double) mbA / (double) this.montantFacturer) * 10000.0D) / 100.0D;

        SwingUtilities.invokeLater(new Runnable() {
            public void run() {
                HistoriqueAffaireBilanPanel.this.labelAvoir.setText(motifAvoir);
                HistoriqueAffaireBilanPanel.this.labelPourcentCommande.setText(decimalFormat.format(pourcentCommande) + "% des commandes livrées");

                // HistoriqueAffaireBilanPanel.this.labelPercentMBPreBilan.setText(decimalFormat.format(percentMBPreBilan)
                // + "% MB Prébilan");
                HistoriqueAffaireBilanPanel.this.labelPercentMBBilan.setText(decimalFormat.format(percentMBBilan) + "% MB sur commande");
                HistoriqueAffaireBilanPanel.this.labelPercentMBAchat.setText(decimalFormat.format(percentMBAchat) + "% MB Achats");
                HistoriqueAffaireBilanPanel.this.labelCommandeClient.setText("Montant du marché : " + GestionDevise.currencyToString(montantCommandeClient) + "€");
                HistoriqueAffaireBilanPanel.this.labelFacturer.setText("Montant facturé : " + GestionDevise.currencyToString(montantFacturer) + "€");
                HistoriqueAffaireBilanPanel.this.labelAchat.setText("Total Achats : " + GestionDevise.currencyToString(montantAchat) + "€");
                HistoriqueAffaireBilanPanel.this.labelCommandeP.setText("Total PréBilan : " + GestionDevise.currencyToString(montantCommandeP) + "€");
                HistoriqueAffaireBilanPanel.this.labelCommande.setText("Total Commandes F. : " + GestionDevise.currencyToString(montantCommande) + "€");
                HistoriqueAffaireBilanPanel.this.labelBudget.setText("Budget chiffré à : " + GestionDevise.currencyToString(montantBudget) + "€");
                HistoriqueAffaireBilanPanel.this.labelMontantRegler.setText("Règlements effectués : " + GestionDevise.currencyToString(montantRegler) + "€");
                HistoriqueAffaireBilanPanel.this.labelRestantFacturer.setText("Reste à facturer : " + GestionDevise.currencyToString(montantCommandeClient - montantFacturer - montantRemise) + "€");
                HistoriqueAffaireBilanPanel.this.labelPercentMargeHT.setText("Marge HT : " + GestionDevise.currencyToString(mbB) + "€");
            }
        });

    }
}
