package com.roxstudio.i18n;

import haxe.Resource;

#if haxe3

private typedef Hash<T> = Map<String, T>;
private typedef IntHash<T> = Map<Int, T>;

#end

/**
* This class provides run-time support for I18n class, all references to the methods of this class
* are generated by I18n at compile-time. Developers must NOT invoke these methods directly
* NOR import this class explicitly, otherwise unexpected problems might be caused by the wrong compile-sequence.
**/
class Global {

    private static inline var DEFAULT = "default";
    private static var supportedLocales: Array<String> = I18n.getSupportedLocales();
    private static var currentLocale: String = DEFAULT;
    private static var map: IntHash<String> = null;
    private static var assetsDir: String = I18n.getAssetsDir();
    private static var absenceResources: Hash<Int> = new Hash();
    private static var listeners: Hash<Void -> Void> = new Hash();

    private function new() {
    }

    #if haxe3 @:noCompletion #end
    public static function init() : Void {
        if (supportedLocales.length == 0)
            throw "This class is for used with 'global' locale only.";
        for (s in I18n.getAbsenceResources()) absenceResources.set(s, 1);
//        trace(absenceResources);
        setCurrentLocale(DEFAULT);
    }

    #if haxe3 @:noCompletion #end
    public static inline function str(id: Int) : String {
        return map.get(id);
    }

    #if haxe3 @:noCompletion #end
    public static inline function res(path: String) : String {
        var locPath = currentLocale + "/" + path;
        if (absenceResources.exists(locPath)) locPath = DEFAULT + "/" + path;
        return assetsDir + "/" + locPath;
    }

    #if haxe3 @:noCompletion #end
    public static inline function addListener(key: String, callb: Void -> Void) : Void {
        listeners.set(key, callb);
    }

    #if haxe3 @:noCompletion #end
    public static function setCurrentLocale(locale: String) : String {
        if (!Lambda.has(supportedLocales, locale)) locale = DEFAULT;
        if (currentLocale == locale && map != null) return locale;
        var resName = "__rox_i18n_strings_" + locale;
        map = new IntHash();
//        var s = Assets.getText(resName);
        var s = Resource.getString(resName);
        if (s == null || s.length == 0)
            throw "Cannot load Resource " + resName + ".";
        var xml = Xml.parse(s);
        for (n in xml.firstElement().elements()) {
            var id = Std.parseInt(n.get("id"));
            var val = n.firstChild().nodeValue;
            map.set(id, val);
        }
        currentLocale = locale;
        for (callb in listeners) callb();
        return currentLocale;
    }

    #if haxe3 @:noCompletion #end
    public static inline function getCurrentLocale() : String {
        return currentLocale;
    }

}
