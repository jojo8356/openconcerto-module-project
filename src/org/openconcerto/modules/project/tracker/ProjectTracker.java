package org.openconcerto.modules.project.tracker;

import java.awt.AWTException;
import java.awt.BasicStroke;
import java.awt.Color;
import java.awt.Component;
import java.awt.Dimension;
import java.awt.FlowLayout;
import java.awt.Font;
import java.awt.Frame;
import java.awt.Graphics;
import java.awt.Graphics2D;
import java.awt.GridBagConstraints;
import java.awt.GridBagLayout;
import java.awt.GridLayout;
import java.awt.Image;
import java.awt.Insets;
import java.awt.MenuItem;
import java.awt.MouseInfo;
import java.awt.Point;
import java.awt.PopupMenu;
import java.awt.RenderingHints;
import java.awt.SystemTray;
import java.awt.TrayIcon;
import java.awt.Window.Type;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.awt.event.MouseAdapter;
import java.awt.event.MouseEvent;
import java.awt.image.BufferedImage;
import java.util.ArrayList;
import java.util.List;

import javax.swing.ButtonGroup;
import javax.swing.JButton;
import javax.swing.JComponent;
import javax.swing.JFrame;
import javax.swing.JLabel;
import javax.swing.JPanel;
import javax.swing.JScrollPane;
import javax.swing.JTabbedPane;
import javax.swing.JTable;
import javax.swing.SwingConstants;
import javax.swing.SwingUtilities;
import javax.swing.UIManager;
import javax.swing.table.DefaultTableCellRenderer;

public class ProjectTracker {
    private static final Color BLUE = Color.decode("#0097A7");
    private static final Color BG_LIGHT_GRAY = new Color(240, 240, 240);
    private boolean active = true;
    List<TrackedProject> l = new ArrayList<TrackedProject>();

    public ProjectTracker() {
        l.add(new TrackedProject("EDF - site internet"));
        final TrackedProject pr = new TrackedProject("Logo SNCF ");
        l.add(pr);

        Thread t = new Thread(new Runnable() {

            @Override
            public void run() {
                Point oldPoint = MouseInfo.getPointerInfo().getLocation();
                int c = 0;
                while (true) {
                    Point p = MouseInfo.getPointerInfo().getLocation();
                    if (p.equals(oldPoint)) {
                        c++;
                        if (c > 5 && isActive()) {
                            setActive(false);
                        }
                    } else {
                        c = 0;
                        if (!isActive()) {
                            setActive(true);
                        }
                    }
                    oldPoint = p;
                    try {
                        Thread.sleep(1 * 1000);
                        refresh();

                    } catch (InterruptedException e) {
                        // TODO Auto-generated catch block
                        e.printStackTrace();
                    }

                }
            }
        });
        t.setDaemon(true);
        t.start();
    }

    protected void refresh() {
        SwingUtilities.invokeLater(new Runnable() {

            @Override
            public void run() {
                createContent.repaint();
                dataModel.fireTableDataChanged();
                updateTrayIcon();
            }
        });

    }

    protected synchronized void setActive(boolean b) {
        this.active = b;
        System.out.println("ProjectTracker.setActive() " + b);
    }

    public synchronized boolean isActive() {
        return active;
    }

    public static void main(String[] args) throws InterruptedException {
        ProjectTracker t = new ProjectTracker();
        t.showFrame();

    }

    public JComponent createContent;
    protected JComponent detailsContent;
    private ProjectTableModel dataModel;
    JFrame f;

    private void showFrame() {
        SwingUtilities.invokeLater(new Runnable() {

            @Override
            public void run() {
                if (f == null) {
                    try {
                        UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName());
                    } catch (Exception e) {
                        e.printStackTrace();
                    }
                    f = new JFrame("OpenConcerto");
                    f.setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);
                    JTabbedPane tPane = new JTabbedPane();
                    createContent = createContent();
                    detailsContent = createDetailsContent();
                    tPane.addTab("Projets", createContent);
                    tPane.addTab("Détails", detailsContent);
                    f.setContentPane(tPane);

                    f.pack();
                    initTray();

                }
                f.setVisible(true);

            }

        });

    }

    void toggleFrame() {
        SwingUtilities.invokeLater(new Runnable() {

            @Override
            public void run() {
                if (f != null) {
                    f.setVisible(!f.isVisible());
                }
            }
        });
    }

    protected JComponent createDetailsContent() {
        JTable t = new JTable();
        t.setRowHeight(t.getRowHeight() + 4);
        dataModel = new ProjectTableModel(l);
        t.setModel(dataModel);
        t.getColumnModel().getColumn(0).setMinWidth(150);
        t.getColumnModel().getColumn(0).setCellRenderer(new DefaultTableCellRenderer() {

            @Override
            public Component getTableCellRendererComponent(JTable table, Object value, boolean isSelected, boolean hasFocus, int row, int column) {

                final Component tableCellRendererComponent = super.getTableCellRendererComponent(table, value, isSelected, hasFocus, row, column);
                setFont(getFont().deriveFont(Font.BOLD));
                if (row == table.getModel().getRowCount() - 1) {
                    setBackground(Color.GRAY);
                    setForeground(Color.WHITE);
                } else if (!isSelected) {
                    setBackground(Color.WHITE);
                    setForeground(Color.BLACK);
                }
                return tableCellRendererComponent;
            }
        });
        for (int i = 1; i < t.getColumnCount(); i++) {
            t.getColumnModel().getColumn(i).setCellRenderer(new DefaultTableCellRenderer() {
                {
                    setHorizontalAlignment(SwingConstants.RIGHT);
                }

                @Override
                public Component getTableCellRendererComponent(JTable table, Object value, boolean isSelected, boolean hasFocus, int row, int column) {

                    final Component tableCellRendererComponent = super.getTableCellRendererComponent(table, value, isSelected, hasFocus, row, column);

                    if (row == table.getModel().getRowCount() - 1) {
                        setBackground(Color.LIGHT_GRAY);
                        setForeground(Color.BLACK);
                    } else if (!isSelected) {
                        setBackground(Color.WHITE);
                        setForeground(Color.BLACK);
                    }
                    return tableCellRendererComponent;
                }
            });
        }

        final JScrollPane jScrollPane = new JScrollPane(t);
        jScrollPane.setPreferredSize(new Dimension(420, 50));
        return jScrollPane;
    }

    private JComponent createContent() {
        JPanel p = new JPanel();
        p.setLayout(new GridLayout(this.l.size(), 1));
        for (TrackedProject trackedProject : l) {
            p.add(createProjectPanel(trackedProject));
        }

        return p;
    }

    private JPanel createProjectPanel(final TrackedProject trackedProject) {
        JPanel p = new JPanel();
        p.setLayout(new GridBagLayout());
        p.setOpaque(true);
        p.setBackground(Color.WHITE);
        GridBagConstraints c = new GridBagConstraints();
        c.insets = new Insets(2, 3, 2, 2);
        c.fill = GridBagConstraints.HORIZONTAL;
        c.anchor = GridBagConstraints.WEST;
        c.gridx = 0;
        c.gridy = 0;
        c.weightx = 1;
        JLabel b = new JLabel(trackedProject.getTitle());
        p.add(b, c);
        c.gridy++;
        p.add(createInfoSelector(trackedProject), c);
        c.gridx++;
        c.gridy = 0;
        c.gridheight = 2;
        c.fill = GridBagConstraints.BOTH;
        c.weightx = 0;
        c.weighty = 1;

        final JLabel timeLabel = new JLabel("II:II", SwingConstants.CENTER) {
            @Override
            public String getText() {
                return trackedProject.getTotalDuration();
            }

            @Override
            public Dimension getMinimumSize() {
                return new Dimension(100, super.getMinimumSize().height);
            }

            @Override
            public Dimension getPreferredSize() {
                return new Dimension(100, super.getPreferredSize().height);

            }
        };
        timeLabel.setFont(timeLabel.getFont().deriveFont(Font.BOLD, 14));
        p.add(timeLabel, c);

        c.gridx++;
        p.add(createCounter(trackedProject), c);
        return p;
    }

    private Component createCounter(final TrackedProject trackedProject) {
        JPanel p = new JPanel() {
            @Override
            protected void paintComponent(Graphics g) {
                Graphics2D g2 = (Graphics2D) g;
                g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
                if (trackedProject.getState() == TrackedProject.STATE_RUNNING) {
                    g.setColor(BLUE);
                } else {
                    g.setColor(BG_LIGHT_GRAY);
                }
                int s = Math.min(getWidth(), getHeight());
                g.fillOval(0, 0, s, s);
                if (trackedProject.getState() != TrackedProject.STATE_RUNNING) {
                    // Play
                    g.setColor(Color.GRAY);
                    g2.setStroke(new BasicStroke(1f));
                    g.fillPolygon(new int[] { (15 * s) / 50, (40 * s) / 50, (15 * s) / 50 }, new int[] { (10 * s) / 50, (25 * s) / 50, (40 * s) / 50 }, 3);
                } else {
                    // Pause
                    g.setColor(Color.WHITE);
                    g2.setStroke(new BasicStroke(6f));
                    g.drawLine((17 * s) / 50, (15 * s) / 50, (17 * s) / 50, (35 * s) / 50);
                    g.drawLine((33 * s) / 50, (15 * s) / 50, (33 * s) / 50, (35 * s) / 50);
                }
            }
        };
        p.setPreferredSize(new Dimension(50, 50));
        p.setMinimumSize(new Dimension(50, 50));
        p.addMouseListener(new MouseAdapter() {
            @Override
            public void mousePressed(MouseEvent e) {
                if (trackedProject.getState() != TrackedProject.STATE_RUNNING) {
                    start(trackedProject);
                } else {
                    stop(trackedProject);
                }
            }
        });
        return p;
    }

    public boolean hasActiveProject() {
        for (TrackedProject trackedProject : l) {
            if (trackedProject.getState() == TrackedProject.STATE_RUNNING) {
                return true;
            }
            ;
        }
        return false;
    }

    protected void start(TrackedProject p) {
        for (TrackedProject trackedProject : l) {
            trackedProject.setState(TrackedProject.STATE_STOPPED);
        }
        p.setState(TrackedProject.STATE_RUNNING);
        createContent.repaint();
    }

    protected void stop(TrackedProject p) {
        for (TrackedProject trackedProject : l) {
            trackedProject.setState(TrackedProject.STATE_STOPPED);
        }
        p.setState(TrackedProject.STATE_STOPPED);
        createContent.repaint();

    }

    private Component createInfoSelector(final TrackedProject trackedProject) {
        JPanel p = new JPanel();
        p.setOpaque(false);
        p.setLayout(new FlowLayout(FlowLayout.LEADING));
        String[] str = trackedProject.getTypes();
        final ButtonGroup g = new ButtonGroup();

        for (int i = 0; i < str.length; i++) {
            final String type = str[i];
            final JButton b = new JButton(type) {
                @Override
                public void paint(Graphics g) {
                    if (isSelected()) {
                        if (trackedProject.getState() == TrackedProject.STATE_STOPPED) {
                            setBackground(Color.GRAY);
                        } else {
                            setBackground(BLUE);
                        }
                        setForeground(Color.WHITE);
                    } else {
                        setBackground(BG_LIGHT_GRAY);
                        setForeground(Color.GRAY);
                    }
                    super.paint(g);
                }

            };
            if (i == 0) {
                b.setSelected(true);
            }
            b.setMargin(new Insets(0, 2, 0, 2));
            b.setBorderPainted(false);
            b.setContentAreaFilled(false);
            b.setOpaque(true);
            b.setFocusPainted(false);
            g.add(b);
            p.add(b);
            b.addActionListener(new ActionListener() {

                @Override
                public void actionPerformed(ActionEvent e) {
                    g.setSelected(b.getModel(), true);
                    trackedProject.setCurrentType(type);
                }
            });
        }

        return p;
    }

    boolean lastState = false;

    void updateTrayIcon() {
        boolean a = this.hasActiveProject();
        if (a != lastState) {
            initTray();

            lastState = a;
        }
    }

    protected boolean initTray() {
        // Check the SystemTray is supported
        if (!SystemTray.isSupported()) {
            System.out.println("SystemTray is not supported");
            return false;
        }
        final PopupMenu popup = new PopupMenu();
        final SystemTray tray = SystemTray.getSystemTray();
        final TrayIcon trayIcon = new TrayIcon(createTrayIcon(tray));

        // Create a pop-up menu components
        MenuItem loginItem = new MenuItem("Afficher");

        MenuItem exitItem = new MenuItem("Quitter");

        // Add components to pop-up menu
        popup.add(loginItem);
        popup.addSeparator();

        popup.add(exitItem);

        trayIcon.setPopupMenu(popup);
        trayIcon.addMouseListener(new MouseAdapter() {
            @Override
            public void mouseClicked(MouseEvent e) {
                System.out.println("ProjectTracker.initTray().new MouseAdapter() {...}.mouseClicked()" + this);
                if (e.getButton() == MouseEvent.BUTTON3) {
                    final Frame frame = new Frame("");
                    frame.setUndecorated(true);
                    frame.setType(Type.UTILITY);
                    frame.setResizable(false);
                    frame.add(popup);
                    frame.setVisible(true);

                } else {
                    toggleFrame();
                }
            }
        });
        loginItem.addActionListener(new ActionListener() {

            @Override
            public void actionPerformed(ActionEvent e) {
                System.out.println("ProjectTracker.initTray().new ActionListener() {...}.actionPerformed()");
                showFrame();
            }
        });
        exitItem.addActionListener(new ActionListener() {

            @Override
            public void actionPerformed(ActionEvent e) {
                System.exit(0);
            }
        });

        try {
            if (tray.getTrayIcons().length > 0)
                tray.remove(tray.getTrayIcons()[0]);
            tray.add(trayIcon);
            return true;
        } catch (AWTException e) {
            System.out.println("TrayIcon could not be added.");
            return false;
        }

    }

    private Image createTrayIcon(SystemTray tray) {
        Dimension trayIconSize = tray.getTrayIconSize();
        final int width = trayIconSize.width;
        final int height = trayIconSize.height;
        BufferedImage off_Image = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);

        Graphics2D g2 = off_Image.createGraphics();
        g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        if (this.hasActiveProject()) {
            g2.setColor(BLUE);
        } else {
            g2.setColor(Color.GRAY);
        }
        g2.fillRect(0, 0, width, height);
        g2.setColor(Color.WHITE);
        float s = Math.min(width, height);
        g2.fillPolygon(new int[] { (int) (15 * s) / 50, (int) (40 * s) / 50, (int) (15 * s) / 50 }, new int[] { (int) (10 * s) / 50, (int) (26 * s) / 50, (int) (42 * s) / 50 }, 3);

        return off_Image;

    }

}
