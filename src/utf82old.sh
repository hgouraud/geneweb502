#!/bin/sh

cat $1 |
sed -e 's/"/@/g' -e 's/\$/\$/g' |
awk '
BEGIN { enc="" }
function disp() {
    if (enc == "ar") ;
    else if (enc == "iso-8859-3")
        system("echo \"" $0 "\" | iconv -f utf-8 -t " enc " | sed -e 's/�/cx/g' -e 's/�/gx/g' -e 's/�/jx/g' -e 's/�/sx/g' -e 's/�/ux/g'")
    else if (enc == "iso-8859-8")
        system("echo \"" $0 "\" | iconv -f utf-8 -t " enc " | sed -e \"s/he: \\([����]\\)/he:  \\1/\" -e \"s|/\\([����]\\)|/ \\1|g\"")
    else if (enc == "lv")
        system("echo \"" $0 "\" | sed -e 's/�\\214/�/g' -e 's/�\\201/�/g' -e 's/�\\206/�/g' -e 's/ļ/�/g' -e 's/�\\215/�/g' -e 's/š/�/g' -e 's/ū/�/g' -e 's/�\\223/�/g' -e 's/Ģ/�/g' -e 's/ģ/�/g' -e 's/Ķ/�/g' -e 's/ī/�/g' -e 's/ķ/�/g' -e 's/þ/�/g'")
    else system("echo \"" $0 "\" | iconv -f utf-8 -t " enc);
    fflush(stdout);
}
function conv(t) { enc=t; disp() }
/^af: / { conv("iso-8859-1"); next }
/^ar: / { enc="ar"; next }
/^bg: / { conv("windows-1251"); next }
/^br: / { conv("iso-8859-1"); next }
/^ca: / { conv("iso-8859-1"); next }
/^cs: / { conv("iso-8859-2"); next }
/^da: / { conv("iso-8859-1"); next }
/^eo: / { conv("iso-8859-3"); next }
/^de: / { conv("iso-8859-1"); next }
/^es: / { conv("iso-8859-1"); next }
/^et: / { conv("iso-8859-15"); next }
/^fi: / { conv("iso-8859-1"); next }
/^fr: / { conv("iso-8859-1"); next }
/^fr-cr: / { conv("iso-8859-1"); next }
/^he: / { conv("iso-8859-8"); next }
/^is: / { conv("iso-8859-1"); next }
/^it: / { conv("iso-8859-1"); next }
/^lv: / { conv("lv"); next }
/^nl: / { conv("iso-8859-1"); next }
/^no: / { conv("iso-8859-1"); next }
/^pl: / { conv("iso-8859-2"); next }
/^pt: / { conv("iso-8859-1"); next }
/^pt-br: / { conv("iso-8859-1"); next }
/^ru: / { conv("windows-1251"); next }
/^sl: / { conv("iso-8859-2"); next }
/^sv: / { conv("iso-8859-1"); next }
/^zh: / { conv("gb2312"); next }
enc== "" { print; next }
/^  / { disp(); next }
{ enc=""; print; next }
' |
sed -e 's/@/"/g'
