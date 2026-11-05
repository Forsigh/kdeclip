package com.forsigh.kdeclip;

import android.util.Log;

import java.lang.reflect.Method;

import io.github.libxposed.api.XposedInterface;
import io.github.libxposed.api.XposedModule;
import io.github.libxposed.api.XposedModuleInterface;

/**
 * Background clipboard access for one package, inside system_server.
 *
 * Android 10+ refuses ClipboardManager reads to any app that is not focused, not the
 * default IME and not a system service. That refusal is raised in
 * com.android.server.clipboard.ClipboardService#clipboardAccessAllowed, which is also the
 * source of the "not in focus nor is it a system service" log line. Forcing that check to
 * true for org.kde.kdeconnect_tp only lets KDE Connect's own clipboard plugin read in the
 * background and send normally. No other package is touched.
 *
 * v1.2.0 adds diagnostics: the allow hook calls through first and logs what the framework
 * would have answered, and getPrimaryClip / getPrimaryClipDescription / hasPrimaryClip are
 * logged for the target package, so a read that is allowed but still comes back empty is
 * visible instead of silent. Results are logged by type only, never by content.
 *
 * Scope is META-INF/xposed/scope.list = "system" (the virtual package name for
 * system_server), so no per-app scope selection is needed in the manager.
 *
 * Overloads are matched by name and return type, not by an exact parameter list: Samsung
 * changed clipboardAccessAllowed's parameters in One UI 7, and a wrong signature fails as
 * silently as a working hook does.
 */
public class Module extends XposedModule {

    private static final String TAG = "kdeclip";
    private static final String VERSION = "v1.3.0";
    private static final String TARGET = "org.kde.kdeconnect_tp";
    private static final String SERVICE = "com.android.server.clipboard.ClipboardService";
    private static final String[] ALLOW_NAMES = {"clipboardAccessAllowed", "isClipboardAccessAllowed"};
    private static final String[] DIAG_NAMES = {"getPrimaryClip", "getPrimaryClipDescription", "hasPrimaryClip"};

    private volatile boolean installed = false;
    private volatile boolean disabled = false;
    private volatile int allowed = 0;
    private volatile int reported = 0;

    @Override
    public void onSystemServerStarting(XposedModuleInterface.SystemServerStartingParam param) {
        install(param.getClassLoader(), "systemServerStarting");
    }

    @Override
    public void onPackageLoaded(XposedModuleInterface.PackageLoadedParam param) {
        if (!"android".equals(param.getPackageName())) {
            return;
        }
        install(param.getDefaultClassLoader(), "packageLoaded(android)");
    }

    private synchronized void install(ClassLoader cl, String source) {
        if (installed || disabled) {
            return;
        }
        int allowHooks = 0;
        int diagHooks = 0;
        try {
            Class<?> service = Class.forName(SERVICE, false, cl == null ? Module.class.getClassLoader() : cl);
            for (Method method : service.getDeclaredMethods()) {
                String name = method.getName();
                if (in(ALLOW_NAMES, name) && method.getReturnType() == boolean.class) {
                    if (hookAllow(method)) {
                        allowHooks++;
                    }
                } else if (in(DIAG_NAMES, name)) {
                    if (hookDiag(method)) {
                        diagHooks++;
                    }
                }
            }
            installed = allowHooks > 0;
        } catch (Throwable t) {
            disabled = true;
            log(Log.ERROR, TAG, "clipboard service not found, module inert", t);
        }
        log(Log.INFO, TAG, VERSION + " via " + source + " allow=" + allowHooks
                + " diag=" + diagHooks + " api=" + getApiVersion());
    }

    private static boolean in(String[] names, String name) {
        for (String candidate : names) {
            if (candidate.equals(name)) {
                return true;
            }
        }
        return false;
    }

    private static boolean isTarget(Object[] args) {
        for (Object arg : args) {
            if (arg instanceof String && TARGET.equals(arg)) {
                return true;
            }
        }
        return false;
    }

    private static String describe(Object value) {
        if (value == null) {
            return "null";
        }
        try {
            Method count = value.getClass().getMethod("getItemCount");
            return value.getClass().getSimpleName() + "/items=" + count.invoke(value);
        } catch (Throwable ignored) {
            return value.getClass().getSimpleName();
        }
    }

    private boolean hookAllow(Method method) {
        try {
            XposedInterface.HookBuilder builder = hook(method);
            builder.setId("kdeclip_" + method.getName() + "_" + method.getParameterCount());
            try {
                builder.setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE);
            } catch (Throwable ignored) {
                // Runtime without exception modes; the catch-all below still applies.
            }
            builder.intercept(chain -> {
                if (disabled) {
                    return chain.proceed();
                }
                Object[] args = chain.getArgs().toArray();
                if (!isTarget(args)) {
                    return chain.proceed();
                }
                if (allowed < 40) {
                    allowed++;
                    log(Log.INFO, TAG, "allowing " + TARGET + " via " + method.getName());
                }
                return Boolean.TRUE;
            });
            return true;
        } catch (Throwable t) {
            log(Log.ERROR, TAG, "hook " + method.getName() + " failed", t);
            return false;
        }
    }

    private boolean hookDiag(Method method) {
        try {
            XposedInterface.HookBuilder builder = hook(method);
            builder.setId("kdeclip_diag_" + method.getName() + "_" + method.getParameterCount());
            try {
                builder.setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE);
            } catch (Throwable ignored) {
                // As above.
            }
            builder.intercept(chain -> {
                boolean target;
                try {
                    target = isTarget(chain.getArgs().toArray());
                } catch (Throwable t) {
                    return chain.proceed();
                }
                Object result = chain.proceed();
                if (target && reported < 40) {
                    reported++;
                    log(Log.INFO, TAG, method.getName() + "(" + method.getParameterCount()
                            + ") for " + TARGET + " -> " + describe(result));
                }
                return result;
            });
            return true;
        } catch (Throwable t) {
            log(Log.ERROR, TAG, "diag hook " + method.getName() + " failed", t);
            return false;
        }
    }
}
