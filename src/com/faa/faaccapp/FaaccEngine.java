package com.faa.faaccapp;

import android.content.Context;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * FaaccEngine — cleaner built-in (tanpa module Magisk).
 * Skrip assets/engine.sh disalin ke filesDir lalu dijalankan via root:
 * {@code su -c '.../engine.sh --scan pkg...'}.
 * Cakupan AGRESIF: cache + code_cache internal, cache eksternal.
 */
public class FaaccEngine {

    private static final String ASSET = "engine.sh";
    private static final String BIN = "engine.sh";

    /** Validasi nama package ala Java (mirror engine.sh). */
    public static boolean validPackage(String pkg) {
        if (pkg == null || pkg.length() == 0) {
            return false;
        }
        if (pkg.indexOf('/') >= 0 || pkg.indexOf(' ') >= 0) {
            return false;
        }
        if (!pkg.matches("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+")) {
            return false;
        }
        if (pkg.equals("android")
                || pkg.equals("com.android.systemui")
                || pkg.equals("com.android.phone")) {
            return false;
        }
        return true;
    }

    /** Pastikan engine.sh ada di filesDir + executable. */
    public static File ensure(Context ctx) {
        try {
            File out = new File(ctx.getFilesDir(), BIN);
            InputStream in = null;
            OutputStream os = null;
            try {
                in = ctx.getAssets().open(ASSET);
                os = new FileOutputStream(out);
                byte[] buf = new byte[8192];
                int n;
                while ((n = in.read(buf)) != -1) {
                    os.write(buf, 0, n);
                }
            } finally {
                if (in != null) {
                    try {
                        in.close();
                    } catch (Exception ignored) {
                    }
                }
                if (os != null) {
                    try {
                        os.close();
                    } catch (Exception ignored) {
                    }
                }
            }
            out.setExecutable(true, false);
            if (out.canExecute()) {
                return out;
            }
        } catch (Exception ignored) {
        }
        return null;
    }

    private static String quote(String s) {
        return "'" + s.replace("'", "'\\''") + "'";
    }

    /**
     * Scan 1 chunk package. Return map pkg -> {total, internal, cc, ext},
     * atau null bila gagal/timeout.
     */
    public static Map<String, long[]> scanChunk(Context ctx, File bin,
                                                List<String> pkgs) {
        Map<String, long[]> out = new HashMap<String, long[]>();
        if (bin == null || pkgs == null || pkgs.isEmpty()) {
            return out;
        }
        StringBuilder sb = new StringBuilder();
        for (String p : pkgs) {
            if (validPackage(p)) {
                if (sb.length() > 0) {
                    sb.append(' ');
                }
                sb.append(p);
            }
        }
        if (sb.length() == 0) {
            return out;
        }
        RootShell.Result r = RootShell.exec(
                quote(bin.getAbsolutePath()) + " --scan " + sb.toString(),
                120000);
        if (r == null || r.timedOut || r.code != 0) {
            return null;
        }
        String[] lines = r.out.split("\n");
        for (String ln : lines) {
            if (ln == null) {
                continue;
            }
            ln = ln.trim();
            if (ln.length() == 0) {
                continue;
            }
            String[] f = ln.split("\\|", -1);
            if (f.length < 5) {
                continue;
            }
            try {
                long[] v = new long[4];
                v[0] = Long.parseLong(f[1]);
                v[1] = Long.parseLong(f[2]);
                v[2] = Long.parseLong(f[3]);
                v[3] = Long.parseLong(f[4]);
                out.put(f[0], v);
            } catch (Exception ignored) {
            }
        }
        return out;
    }

    /**
     * Clean 1 package. Return {freed_bytes, rc} atau null bila gagal.
     * rc: 0 sukses, 2 tak-ada cache, lain = gagal/abort.
     */
    public static long[] cleanPkg(Context ctx, File bin, String pkg) {
        if (bin == null || !validPackage(pkg)) {
            return null;
        }
        RootShell.Result r = RootShell.exec(
                quote(bin.getAbsolutePath()) + " --clean " + pkg, 180000);
        if (r == null || r.timedOut) {
            return null;
        }
        String[] lines = r.out.split("\n");
        for (String ln : lines) {
            if (ln == null) {
                continue;
            }
            ln = ln.trim();
            if (ln.length() == 0) {
                continue;
            }
            String[] f = ln.split("\\|", -1);
            if (f.length < 3 || !f[0].equals(pkg)) {
                continue;
            }
            try {
                return new long[]{Long.parseLong(f[1]),
                        Long.parseLong(f[2])};
            } catch (Exception ignored) {
                return null;
            }
        }
        return null;
    }
}
