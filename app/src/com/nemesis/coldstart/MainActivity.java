package com.nemesis.coldstart;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import java.io.BufferedReader;
import java.io.InputStreamReader;

/**
 * Cold-start Heat, always-on edition. No temperature sensor: on every start the
 * service applies the wheel and seat actions chosen here. Writes one-value
 * config files through the privileged `nemesis root` channel.
 */
public class MainActivity extends Activity {

    static final String STATE = "/data/nemesis/state/coldstart.heat";
    static final String NEM = "/system/xbin/nemesis";
    static final String[] LEVEL = { "No action", "1 (Low)", "2 (Med)", "3 (High)" };

    boolean enabled = true;
    boolean wheel = true;
    int seatDrv = 0;      // 0..3
    int seatPass = 0;     // 0..3
    boolean cool = false; // false = heat, true = cool/vent (needs vent_enum_1..3)
    boolean logging = false;

    TextView statusLabel;
    Button enBtn, wheelBtn, modeBtn, drvBtn, passBtn, logBtn;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        loadConfig();

        ScrollView sv = new ScrollView(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(20);
        root.setPadding(pad, pad, pad, pad);
        root.setBackgroundColor(Color.rgb(18, 20, 24));
        sv.addView(root);

        root.addView(title("Cold-start Heat"));
        root.addView(hint("Every time the car starts, the choices below are applied. "
                + "The outside temperature is not checked."));

        enBtn = new Button(this);
        enBtn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { enabled = !enabled; refresh(); }
        });
        root.addView(enBtn);

        root.addView(gap());
        root.addView(section("Steering wheel"));
        wheelBtn = new Button(this);
        wheelBtn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { wheel = !wheel; refresh(); }
        });
        root.addView(wheelBtn);

        root.addView(gap());
        root.addView(section("Seats"));
        modeBtn = new Button(this);
        modeBtn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { cool = !cool; refresh(); }
        });
        root.addView(modeBtn);
        root.addView(hint("Cool uses your car's ventilation codes, which are not "
                + "built in. Until vent_enum_1/2/3 are set (see EXTENDING.md), Cool "
                + "does nothing."));

        drvBtn = new Button(this);
        drvBtn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { seatDrv = (seatDrv + 1) % 4; refresh(); }
        });
        root.addView(drvBtn);

        passBtn = new Button(this);
        passBtn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { seatPass = (seatPass + 1) % 4; refresh(); }
        });
        root.addView(passBtn);

        root.addView(gap());
        Button save = new Button(this);
        save.setText("Save");
        save.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { saveConfig(); }
        });
        root.addView(save);

        Button test = new Button(this);
        test.setText("Test now");
        test.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { testNow(); }
        });
        root.addView(test);

        Button off = new Button(this);
        off.setText("All heaters OFF now");
        off.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { allOff(); }
        });
        root.addView(off);

        root.addView(gap());
        root.addView(section("Settings"));
        logBtn = new Button(this);
        logBtn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { logging = !logging; saveLogging(); refresh(); }
        });
        root.addView(logBtn);
        Button usb = new Button(this);
        usb.setText("Copy logs to USB (then clear)");
        usb.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { copyLogsToUsb(); }
        });
        root.addView(usb);

        statusLabel = new TextView(this);
        statusLabel.setTextColor(Color.rgb(140, 160, 180));
        statusLabel.setPadding(0, dp(16), 0, 0);
        root.addView(statusLabel);

        setContentView(sv);
        refresh();
    }

    void refresh() {
        enBtn.setText(enabled ? "Automation: ON" : "Automation: OFF");
        wheelBtn.setText("Always heat steering wheel:  " + (wheel ? "ON" : "off"));
        modeBtn.setText("Seat mode:  " + (cool ? "Cool (needs codes)" : "Heat"));
        drvBtn.setText("Driver seat:  " + LEVEL[seatDrv]);
        passBtn.setText("Passenger seat:  " + LEVEL[seatPass]);
        logBtn.setText("Logging:  " + (logging ? "ON" : "off"));
    }

    // ---- config I/O via `nemesis root -c` -------------------------------
    String runRoot(String cmd) {
        StringBuilder out = new StringBuilder();
        try {
            Process p = Runtime.getRuntime().exec(new String[] { NEM, "root", "-c", cmd });
            BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String line;
            while ((line = r.readLine()) != null) out.append(line).append("\n");
            p.waitFor();
        } catch (Exception e) {
            return "ERR " + e.getMessage();
        }
        return out.toString();
    }

    int readInt(String name, int def) {
        String v = runRoot("cat " + STATE + "/" + name + " 2>/dev/null").trim();
        try { return Integer.parseInt(v.trim()); } catch (Exception e) { return def; }
    }

    void loadConfig() {
        enabled = readInt("enabled", 1) == 1;
        wheel   = readInt("wheel", 1) == 1;
        seatDrv = clamp(readInt("seat_drv", 0), 0, 3);
        seatPass= clamp(readInt("seat_pass", 0), 0, 3);
        cool    = readInt("seat_mode", 0) == 1;
        logging = readInt("logging", 0) == 1;
    }

    void saveConfig() {
        String cmd = "mkdir -p " + STATE
            + "; echo " + (enabled ? 1 : 0) + " > " + STATE + "/enabled"
            + "; echo " + (wheel ? 1 : 0) + " > " + STATE + "/wheel"
            + "; echo " + seatDrv + " > " + STATE + "/seat_drv"
            + "; echo " + seatPass + " > " + STATE + "/seat_pass"
            + "; echo " + (cool ? 1 : 0) + " > " + STATE + "/seat_mode";
        String r = runRoot(cmd);
        if (r.startsWith("ERR")) toast("Save failed: " + r);
        else { toast("Saved"); statusLabel.setText("Saved: every start -> wheel " + (wheel ? "on" : "off")
            + ", " + (cool ? "cool" : "heat") + " drv " + LEVEL[seatDrv] + ", pass " + LEVEL[seatPass]); }
    }


    void saveLogging() {
        String r = runRoot("mkdir -p " + STATE + "; echo " + (logging ? 1 : 0) + " > " + STATE + "/logging");
        if (r.startsWith("ERR")) toast("Save failed: " + r);
        else toast(logging ? "Logging on" : "Logging off");
    }

    // Copies run.log to the first writable USB volume; clears the on-unit log only if the copy is non-empty.
    void copyLogsToUsb() {
        String L = STATE + "/run.log";
        String cmd = "if [ ! -s " + L + " ] && [ ! -s " + L + ".1 ]; then echo NOLOG; exit 0; fi; "
            + "list=\"$(grep -E ' (vfat|exfat|ntfs|sdfat|texfat|fuseblk|msdos) ' /proc/mounts | while read a b c r; do echo $b; done) "
            + "$(ls -d /storage/*/ /storage/*/*/ /mnt/media_rw/*/ /mnt/usb*/ /mnt/*/ 2>/dev/null)\"; "
            + "tried=''; "
            + "for d in $list; do d=${d%/}; "
            + "case \"$d\" in ''|*/emulated*|*/self*|*/sdcard*|/mnt/runtime*|/mnt/user*|/mnt/shell*|/mnt/obb*|/mnt/asec*|/mnt/secure*|/mnt/expand*|/mnt/androidwritable*|/mnt/pass_through*|/mnt/installer*|/mnt/vendor*) continue;; esac; "
            + "[ -d \"$d\" ] || continue; "
            + "tried=\"$tried $d\"; "
            + "touch \"$d/.cs_w\" 2>/dev/null || continue; rm -f \"$d/.cs_w\"; "
            + "o=\"$d/coldstart-log-$(date +%Y%m%d-%H%M%S).txt\"; "
            + "cat " + L + ".1 " + L + " > \"$o\" 2>/dev/null; sync; "
            + "if [ -s \"$o\" ]; then rm -f " + L + " " + L + ".1; echo OK:$o; exit 0; else rm -f \"$o\"; fi; done; "
            + "echo NOUSB:$tried";
        String r = runRoot(cmd).trim();
        String msg;
        if (r.startsWith("OK:")) msg = "Copied to " + r.substring(3) + " and cleared";
        else if (r.equals("NOLOG")) msg = "No logs saved on the unit. Turn Logging ON, then sleep/wake the car, then try again.";
        else if (r.startsWith("NOUSB")) msg = "No writable USB found. Logs kept. Folders tried: " + (r.length() > 6 ? r.substring(6) : "none") + ". Re-seat the stick (FAT32/exFAT) and retry.";
        else msg = "Copy failed - logs kept. Output: " + (r.length() > 200 ? r.substring(0, 200) : r);
        toast(msg);
        statusLabel.setText(msg);
    }
    // heat: UI level 1/2/3 -> 6/7/8. cool: read vent_enum_<n> on the unit; -1 = not set.
    int seatEnum(int lvl) {
        if (cool) return readInt("vent_enum_" + lvl, -1);
        switch (lvl) { case 1: return 6; case 2: return 7; case 3: return 8; default: return 2; }
    }

    void testNow() {
        StringBuilder c = new StringBuilder();
        String skipped = "";
        if (wheel) c.append("service call com.hkmc.vr 16 i32 1; ");
        if (seatDrv > 0) {
            int e = seatEnum(seatDrv);
            if (e < 0) skipped += " driver"; else c.append("service call com.hkmc.micom.usm 213 i32 ").append(e).append("; ");
        }
        if (seatPass > 0) {
            int e = seatEnum(seatPass);
            if (e < 0) skipped += " passenger"; else c.append("service call com.hkmc.micom.usm 214 i32 ").append(e).append("; ");
        }
        if (c.length() == 0) { toast(skipped.length() > 0 ? "No vent codes set" : "Nothing selected"); }
        else runRoot(c.toString());
        statusLabel.setText("Applied now: wheel " + (wheel ? "on" : "off")
            + ", drv " + LEVEL[seatDrv] + ", pass " + LEVEL[seatPass]
            + (skipped.length() > 0 ? "  (skipped, no vent codes:" + skipped + ")" : ""));
    }

    void allOff() {
        runRoot("service call com.hkmc.vr 16 i32 0; service call com.hkmc.micom.usm 213 i32 2; "
              + "service call com.hkmc.micom.usm 214 i32 2");
        statusLabel.setText("All heaters commanded off.");
        toast("Off");
    }

    // ---- small view helpers --------------------------------------------
    int dp(int v) { return (int) (v * getResources().getDisplayMetrics().density); }
    int clamp(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }
    void toast(String s) { Toast.makeText(this, s, Toast.LENGTH_SHORT).show(); }

    TextView title(String s) {
        TextView t = new TextView(this);
        t.setText(s); t.setTextColor(Color.WHITE); t.setTextSize(26);
        t.setPadding(0, 0, 0, dp(8)); return t;
    }
    TextView section(String s) {
        TextView t = new TextView(this);
        t.setText(s); t.setTextColor(Color.rgb(120, 180, 255)); t.setTextSize(16);
        t.setPadding(0, dp(8), 0, dp(4)); return t;
    }
    TextView hint(String s) {
        TextView t = new TextView(this);
        t.setText(s); t.setTextColor(Color.rgb(150, 160, 170)); t.setTextSize(13);
        t.setPadding(0, 0, 0, dp(12)); return t;
    }
    View gap() { View v = new View(this); v.setMinimumHeight(dp(10)); return v; }
}
