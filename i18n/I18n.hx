package i18n;

import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;
using Lambda;
using StringTools;

#if macro
import sys.FileSystem;
import sys.io.File;
#end

private typedef Item = {
    id: Int,
    val: String,
    file: String,
    pos: Array<String>,
}

class I18n {
    macro public static function init() : Expr {
		if (initialized) {
			return Context.parse("{}", Context.currentPos());
		}

        // make working directory
		var defaultPath = Path.join([workDir, DEFAULT]);
		
        if (!FileSystem.exists(defaultPath)) {
            mkdirs(defaultPath);
		}

        // recentLocale is the locale used by previous build
        var recentLocale = DEFAULT;
		var recentPath = Path.join([workDir, 'recentLocale']);

		if (FileSystem.exists(recentPath)) {
            recentLocale = File.getContent(recentPath);
		}

        if (recentLocale != useLocale) {
			rmdir(assetsDir);
		}

        File.saveContent(recentPath, useLocale);

        Context.onGenerate(postCompile);

		// scan for all available locale folders
        for (dir in FileSystem.readDirectory(workDir)) {
            if (FileSystem.isDirectory(Path.join([workDir, dir]))) {
				locales.push(dir);
			}
        }

        var isglobal = useLocale == GLOBAL;
        // make sure only necessary strings.xml are loaded
        var locales = isglobal ? locales : [DEFAULT, useLocale];

        for (loc in locales) {
            var map = new Map<String, String>();

			var stringsPath = Path.join([workDir, loc, 'strings.xml']);
			
            if (FileSystem.exists(stringsPath)) {
                var xml = Xml.parse(File.getContent(stringsPath)).firstElement();

                for (file in xml.elementsNamed('file')) {
                    var path = file.get('path');

                    for (t in file.elementsNamed('t')) {
                        var id = t.get('id');
                        var val = t.firstChild().nodeValue;
                        map.set('$path//$id', val);
                    }
                }
            }

            lookups.set(loc, map);
        }

		if (isglobal) {
            // check for absence resources and build a fallback lookup
            var allRes = listDir(Path.join([workDir, DEFAULT]), '');

            for (loc in locales) {
                if (loc == DEFAULT) {
					continue;
				}

                var locRes = listDir(Path.join([workDir, loc]), '');

                for (file in allRes) {
                    if (file != 'strings.xml' && !locRes.has(file)) {
                        absence.push(Path.join([loc, file]));
					}
                }
            }
        }

        initialized = true;
        return Context.parse(isglobal ? "i18n.Global.init()" : "{}", Context.currentPos());
    }


    macro public static function i18n(s: ExprOf<String>) : Expr {
        if (!initialized) {
			throw "call i18n.I18n.init()";
		}

        var str = expr2Str(s);
        var path = Context.getPosInfos(s.pos).file;
        var id: Int;
        var key = path + "//" + lbEsc(str);
        var val = strings.get(key);
        var pos = ("" + s.pos).split(":")[1];

		if (val != null) {
            val.pos.push(pos);
            id = val.id;
        } else {
            id = counter++;
            strings.set(key, { id: id, val: str, file: path, pos: [ pos ] });
        }

		return switch useLocale {
			case GLOBAL:
				Context.parse("i18n.Global.str(" + id + ")", s.pos);
			default:
				var val = lookups.get(useLocale).get(key);

				if (val == null) {
					val = lookups.get(DEFAULT).get(key);
				}

				if (val == null) {
					val = str;
				}

				Context.parse("'" + quoteEsc(val) + "'", s.pos);
        }
    }

    macro public static function i18nRes(path: ExprOf<String>) : Expr {
        if (!initialized) {
			throw "call i18n.I18n.init()";
		}

        var p = expr2Str(path);
        var defaultPath = Path.join([workDir, DEFAULT, p]);

		if (!FileSystem.exists(defaultPath)) {
			Context.error("Asset:" + defaultPath + " does not exist.", path.pos);
		}

        return switch useLocale {
			case GLOBAL:
				copy(defaultPath, Path.join([assetsDir, DEFAULT, p]));

				for (l in locales) {
					var locPath = Path.join([l, p]);
					var workPath = Path.join([workDir, locPath]);
					
					if (FileSystem.exists(workPath)) {
						copy(workPath, Path.join([assetsDir, locPath]));
					}
				}
				Context.parse("i18n.Global.res('" + p + "')", path.pos);
			default:
				var locPath = useLocale + "/" + p;
				var workPath = Path.join([workDir, locPath]);
				var assetsPath = Path.join([assetsDir, p]);
				
				if (FileSystem.exists(workPath)) {
					copy(workPath, assetsPath);
				} else {
					copy(defaultPath, assetsPath);
				}

				Context.parse("'" + assetsPath + "'", path.pos);
        }
    }

    macro public static function onChange(e: Expr) : Expr {
        var pos = e.pos;
        var key = "" + pos;
        var ln = key.split(":")[1];
        var varname = "__i18n_callb__" + ln + "__" + Std.random(100000000) + "__";

		var callb: Expr = switch (e.expr) {
			case EFunction(n, f):
				n == null && f.args.length == 0 && f.ret == null && f.params.length == 0 ? e : null;
			default: null;
        }

        if (callb == null) {
            callb = { expr: EFunction(null, { args: [], ret: null, params: [], expr: e }), pos: pos };
        }

		var line1 = { expr: EVars([ { name: varname, type: null, expr: callb } ]), pos: pos };
        var line2 = Context.parse("i18n.Global.addListener('" + key + "', " + varname + ")", pos);
        var line3 = Context.parse(varname + "()", pos);

		return useLocale == GLOBAL
			? { expr: EBlock([ line1, line2, line3 ]), pos: pos }
            : { expr: EBlock([ line1, line3 ]), pos: pos };
    }

    macro public static function getSupportedLocales() : Expr {
		return macro {
			$v{useLocale} == $v{GLOBAL}
				? $v{locales}
				: [];
		}			
    }

    macro public static function setCurrentLocale(locExpr: Expr) : Expr {
        var field = Context.parse("i18n.Global.setCurrentLocale", locExpr.pos);
        return { expr: ECall(field, [ locExpr ]), pos: locExpr.pos };
    }

    macro public static function getCurrentLocale() : Expr {
        var field = Context.parse("i18n.Global.getCurrentLocale", Context.currentPos());
        return { expr: ECall(field, []), pos: Context.currentPos() };
    }

    macro public static function getAbsenceResources() : Expr {
        var code = new StringBuf();

		code.add("[");

		if (useLocale == GLOBAL) {
            for (p in absence) {
				code.add("'" + p + "',");
			}
        }

        code.add("]");
        return Context.parse(code.toString(), Context.currentPos());
    }

    macro public static function getAssetsDir() : Expr {
        return Context.parse("'" + assetsDir + "'", Context.currentPos());
    }

/******************************************************************
*       Compiler Options
******************************************************************/

#if macro
    public static function locale(locale: String) {
        //trace("I18n.locale = " + locale);
        useLocale = locale;
    }

    public static function assets(dir: String) {
        //trace("I18n.assets = " + dir);
        assetsDir = dir;
    }
#end

/******************************************************************
*       Private stuff
******************************************************************/

#if macro
    static inline var DEFAULT = "default";
    static inline var GLOBAL = "global";
    static inline var XML_HEAD = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\r\n";

    static var useLocale = DEFAULT;
    static var assetsDir = "assets/i18n";
    static var workDir = "i18n_work";
    static var strings = new Map<String, Item>(); // filepath//id => Item
    static var lookups = new Map<String, Map<String, String>>(); // locale => { filepath//id => String }
    static var locales: Array<String> = [];
    static var absence: Array<String> = [];
    static var initialized = false;
    static var counter = 1;

    static function postCompile(_) {
        //Context.warning("postCompile=" + useLocale, Context.currentPos());
        var defLookup = lookups.get(DEFAULT);
        var all: Array<Item> = strings.array();

		all.sort(function(i1: Item, i2: Item) : Int {
            return Reflect.compare(i1.file + "//" + i1.val, i2.file + "//" + i2.val);
        });

		var path: String = null;
        var fileNode: Xml = null;
        var str = Xml.createElement("strings");

		for (i in all) {
            if (i.file != path) {
                if (fileNode != null) {
					fileNode.addChild(Xml.createPCData("\r\n  "));
				}
				
                path = i.file;
                str.addChild(Xml.createPCData("\r\n  "));
                fileNode = Xml.createElement("file");
                fileNode.set("path", path);
                str.addChild(fileNode);
            }
			
            fileNode.addChild(Xml.createPCData("\r\n    "));
            
			var t = Xml.createElement("t");
            var k = lbEsc(i.val);
            t.set("id", k);
            
			var val = defLookup.get(i.file + "//" + k);
            
			if (val == null) {
				val = i.val;
			}
			
            t.addChild(Xml.createPCData(val));
            fileNode.addChild(t);
            
			var lineinfo = new StringBuf();
            lineinfo.add("line ");
            
			for (l in 0...i.pos.length) {
				if (l > 0) {
					lineinfo.add(", ");
				}
				
				lineinfo.add(i.pos[l]);			
			}
			
            fileNode.addChild(Xml.createComment(lineinfo.toString()));
        }
        
		if (fileNode != null) {
			fileNode.addChild(Xml.createPCData("\r\n  "));
		}
		
        str.addChild(Xml.createPCData("\r\n"));
        File.saveContent(Path.join([workDir, DEFAULT, 'strings.xml']), XML_HEAD + str.toString());

        if (useLocale != GLOBAL) {
			return;
		}

        for (loc in locales) {
            str = Xml.createElement('strings');
            var lookup = lookups.get(loc);
			
            for (key in strings.keys()) {
                var item = strings.get(key);
                var val = lookup.get(key);
            
				if (val == null) {
					val = defLookup.get(key);
				}
				
                if (val == null) {
					val = item.val;
				}
				
                var id = item.id;
                var t = Xml.createElement('t');
                
				t.set('id', '$id');
                t.addChild(Xml.createPCData(val));
                str.addChild(t);
            }

            Context.addResource("__rox_i18n_strings_" + loc, haxe.io.Bytes.ofString(str.toString()));
//            mkdirs(assetsDir + "/" + loc);
//            File.saveContent(assetsDir + "/" + loc + "/strings.xml", str.toString());
        }
    }

    static function mkdirs(path: String) {
//        Context.warning("mkdirs=" + path, Context.currentPos());
        var arr = path.split('/');
        var dir = '';
		
        for (i in 0...arr.length) {
            dir += arr[i];
        
			if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir)) {
                FileSystem.createDirectory(dir);
            }
            
			dir += '/';
        }
    }

    static function rmdir(path: String) {
//        Context.warning("rmdir=" + path, Context.currentPos());
        if (!FileSystem.exists(path) || !FileSystem.isDirectory(path)) {
			return;
		}

        for (name in FileSystem.readDirectory(path)) {
            var sub = path + "/" + name;

            if (FileSystem.isDirectory(sub)) {
                rmdir(sub);
            } else {
                try {
                    FileSystem.deleteFile(sub);
                } catch (ex: Dynamic) {
                    Context.error("Failed removing $sub, you may need to delete the i18n assets directory manually.", Context.currentPos());
                }
            }
        }

        FileSystem.deleteDirectory(path);
    }

    static function copy(src: String, dest: String) {
//        Context.warning("copy " + src+ " to " + dest, Context.currentPos());
        if (FileSystem.exists(dest)) {
            var fs1 = FileSystem.stat(src);
            var fs2 = FileSystem.stat(dest);

			if (fs1.mtime.getTime() <= fs2.mtime.getTime()) {
				return;
			}
        }

        var idx = dest.lastIndexOf("/");
        
		if (idx > 0) {
			mkdirs(dest.substr(0, idx));
		}
        
		File.copy(src, dest);
    }

    static inline function expr2Str(expr: ExprOf<String>) : String {
        var str: String = null;
        
		switch expr.expr {
			case EConst(c):
				switch (c) {
					case CString(s): str = s;
					default:
				}
			default:
        }
        
		if (str == null) {
            Context.error('Constant string expected', expr.pos);
        }
        
		return str;
    }

    static function listDir(path: String, prefix: String, ?out: Array<String>) {
        if (out == null) {
			out = [];
		}
		
        for (file in FileSystem.readDirectory(path)) {
            if (FileSystem.isDirectory(path + "/" + file)) {
                listDir(path + "/" + file, prefix + file + "/", out);
            } else {
                out.push(prefix + file);
            }
        }
        return out;
    }

    static inline function quoteEsc(s: String)
        return s.replace("'", "\\'");

    static inline function lbEsc(s: String)
		return s.replace('\r', '\\r').replace('\n', '\\n');
#end
}
