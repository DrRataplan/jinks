xquery version "3.1";

declare namespace api="https://tei-publisher.com/xquery/api";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace expath="http://expath.org/ns/pkg";

import module namespace config="https://tei-publisher.com/generator/xquery/config" at "config.xql";
import module namespace generator="http://tei-publisher.com/library/generator" at "generator.xql";
import module namespace roaster="http://e-editiones.org/roaster";
import module namespace errors = "http://e-editiones.org/roaster/errors";
import module namespace tmpl="http://e-editiones.org/xquery/templates";

declare option output:method "html5";
declare option output:media-type "text/html";
declare option output:indent "no";

declare function api:generator($request as map(*)) {
    let $config := if ($request?body instance of array(*)) then $request?body?1 else $request?body
    let $profile := $request?parameters?profile
    let $overwrite := $request?parameters?overwrite
    let $dryRun := $request?parameters?dry
    return
        generator:process($profile, map { "overwrite": $overwrite, "dry": $dryRun }, $config)
};

declare function api:expand-template($request as map(*)) {
    let $template := $request?body?template
    let $params := head(($request?body?params, map {}))
    return
        try {
            tmpl:process($template, $params, not($request?body?mode = ('html', 'xml')), function ($relPath as xs:string) {
                let $path := $config:app-root || "/" || $relPath
                return
                    if (util:binary-doc-available($path)) then
                        util:binary-doc($path) => util:binary-to-string()
                    else if (doc-available($path)) then
                        doc($path) => serialize()
                    else
                        ()
            }, true())
        } catch * {
            roaster:response(500, $err:description)
        }
};

declare function api:configurations($request as map(*)) {
    let $installed :=
        for $collection in xmldb:get-child-collections(repo:get-root())
        let $configPath := repo:get-root() || "/" || $collection || "/config.json"
        return
            if (util:binary-doc-available($configPath)) then
                let $config := json-doc($configPath)
                let $expath := generator:get-package-descriptor($config?id)
                return
                    map {
                        "type": "installed",
                        "profile": array:get($config?profiles, array:size($config?profiles)),
                        "title": head(($config?label, $config?pkg?title)),
                        "config": $config
                    }
            else
                ()
    let $profiles :=
        for $collection in xmldb:get-child-collections($config:app-root || "/profiles")
        return
            let $config := generator:profile($collection)
            return
                map {
                    "type": "profile",
                    "profile": $collection,
                    "title": head(($config?label, $config?pkg?title)),
                    "config": $config
                }
    return
        array { $installed, $profiles }
};

declare function api:page($request as map(*)) {
    let $path := $config:app-root || "/pages/" || $request?parameters?page || ".html"
    let $doc :=
        if (util:binary-doc-available($path)) then
            util:binary-doc($path) => util:binary-to-string()
        else if (doc-available($path)) then
            doc($path) => serialize()
        else
            error($errors:NOT_FOUND, $path || " not found")
    let $params := map {
        "context": map {
            "db-root": $config:app-root,
            "path": $config:context-path
        },
        "title": "TEI Publisher Templating"
    }
    return
        tmpl:process($doc, $params, false(), ())
};

let $lookup := function($name as xs:string) {
    try {
        function-lookup(xs:QName($name), 1)
    } catch * {
        ()
    }
}
let $resp := roaster:route("modules/api.json", $lookup)
return
    $resp