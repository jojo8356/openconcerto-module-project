package org.openconcerto.modules.project.tracker;

import java.util.HashMap;
import java.util.Map;

public class TrackedProject {
    public static final int STATE_RUNNING = 0;
    public static final int STATE_PAUSED = 1;
    public static final int STATE_STOPPED = 2;
    private String title;
    private int state = STATE_STOPPED;
    private Map<String, Integer> map = new HashMap<String, Integer>();
    private String type;
    private long timeAtStartInMs = -1;

    public TrackedProject(String title) {
        this.title = title;
        this.type = getTypes()[0];
    }

    public String getTitle() {
        return title;
    }

    public int getState() {
        return state;
    }

    public void setState(int state) {
        if (state != this.state) {

            if (state == STATE_RUNNING) {
                timeAtStartInMs = System.currentTimeMillis() - getDuration(this.type) * 1000;
            } else {
                storeCurrentValue();
            }
            this.state = state;
        }
    }

    private void storeCurrentValue() {
        final Integer s = Integer.valueOf((int) ((System.currentTimeMillis() - timeAtStartInMs) / 1000));
        map.put(type, s);
        System.out.println("TrackedProject.setState() store " + s + " for " + type);
    }

    public String getTotalDuration() {
        String[] s = getTypes();
        int total = 0;
        for (String t : s) {
            total += getDuration(t);
        }
        return formatDuration(total);
    }

    public String[] getTypes() {
        return new String[] { "Etude", "Graphisme", "Dév.", "Tests", "Correctifs" };
    }

    public void setCurrentType(String type) {
        if (state == STATE_RUNNING)
            storeCurrentValue();

        // if (state == STATE_RUNNING) {
        timeAtStartInMs = System.currentTimeMillis() - getDuration(type) * 1000;
        // }
        this.type = type;
    }

    public int getDuration(String type) {
        if (state == STATE_RUNNING && this.type.equals(type) && timeAtStartInMs > 0) {
            return (int) ((System.currentTimeMillis() - timeAtStartInMs) / 1000);
        }
        Integer i = map.get(type);
        if (i == null) {
            i = Integer.valueOf(0);
            map.put(type, i);

        }
        // System.out.println("TrackedProject.getDuration() " + this.getTitle() + " " + type + " : "
        // + i);
        return i;
    }

    public static String formatDuration(int s) {
        int seconds = s % 60;
        int mins = (s / 60) % 60;
        int hours = s / 3600;
        String r = "";
        if (s >= 60) {
            if (hours > 0) {
                r += hours + "h";
            }
            if (hours > 0 && mins < 10) {
                r += "0" + mins + "m";
            } else {
                r += +mins + "m";
            }
        }
        if ((mins + hours) > 0 && seconds < 10) {
            r += "0" + seconds + "s";
        } else {
            r += +seconds + "s";
        }
        return r;
    }

    public static void main(String[] args) {
        for (int i = 0; i < 5000; i++) {
            System.out.println("TrackedProject.main() " + i + " " + formatDuration(i));
        }
    }
}
