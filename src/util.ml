(* camlp5r ./pa_lock.cmo ./pa_html.cmo *)
(* $Id: util.ml,v 5.130 2007-09-12 09:58:44 ddr Exp $ *)
(* Copyright (c) 1998-2007 INRIA *)

open Config;
open Def;
open Gutil;
open Gwdb;
open Mutil;
open Printf;

value sharelib =
  List.fold_right Filename.concat [Gwlib.prefix; "share"] "geneweb"
;

value add_lang_path = Secure.add_lang_path;
value add_doc_path = Secure.add_doc_path;
value set_base_dir = Secure.set_base_dir;

add_lang_path sharelib;
add_lang_path Filename.current_dir_name;

value cnt_dir = ref Filename.current_dir_name;
value images_url = ref "";

value search_in_path p s =
  loop (p ()) where rec loop =
    fun
    [ [d :: dl] ->
        let f = Filename.concat d s in
        if Sys.file_exists f then f else loop dl
    | [] -> s ]
;

value search_in_lang_path = search_in_path Secure.lang_path;
value search_in_doc_path = search_in_path Secure.doc_path;

(* Internationalization *)

value start_with_vowel s =
  if String.length s > 0 then
    match Char.lowercase s.[0] with
    [ 'a' | 'e' | 'i' | 'o' | 'u' -> True
    | _ -> False ]
  else False
;

value start_with_hi_i s =
  if String.length s > 0 then
    match Char.lowercase s.[0] with
    [ 'i' -> True
    | 'h' -> String.length s > 1 && s.[1] = 'i'
    | _ -> False ]
  else False
;

value match_begin s t =
  loop 0 0 where rec loop i j =
    if i >= String.length s || j >= String.length t then True
    else if s.[i] = t.[j] then loop (i + 1) (j + 1)
    else False
;

value amp_capitalize capitale s =
  if String.length s <= 1 then s
  else if match_begin s "&iexcl;" then
    "&iexcl;" ^ capitale (String.sub s 7 (String.length s - 7))
  else if match_begin s "&aelig;" then
    "&AElig;" ^ String.sub s 7 (String.length s - 7)
  else
    match s.[1] with
    [ 'a'..'z' ->
        "&" ^
          String.make 1
            (Char.chr
               (Char.code s.[1] - Char.code 'a' + Char.code 'A')) ^
          String.sub s 2 (String.length s - 2)
    | _ -> s ]
;

value rec capitale_iso_8859_1 s =
  if String.length s = 0 then ""
  else
    match s.[0] with
    [ 'a'..'z' | '�'..'�' | '�'..'�' ->
        String.make 1
          (Char.chr (Char.code s.[0] - Char.code 'a' + Char.code 'A')) ^
          String.sub s 1 (String.length s - 1)
    | '&' -> amp_capitalize capitale_iso_8859_1 s
    | _ -> s ]
;

value rec capitale_utf_8 s =
  if String.length s = 0 then ""
  else
    let c = s.[0] in
    if c = '&' then amp_capitalize capitale_utf_8 s
    else if c = '<' then
      loop 1 where rec loop i =
        if i = String.length s then s
        else if s.[i] = '>' then
          let s1 = String.sub s (i + 1) (String.length s - i - 1) in
          String.sub s 0 (i + 1) ^ capitale_utf_8 s1
        else loop (i + 1)
    else if Char.code c < 0b10000000 then String.capitalize s
    else if String.length s = 1 then s
    else
      match Char.code c with
      [ 0xC3 ->
          let c1 = Char.uppercase (Char.chr (Char.code s.[1] + 0x40)) in
          sprintf "%c%c%s" c (Char.chr (Char.code c1 - 0x40))
            (String.sub s 2 (String.length s - 2))
      | 0xC5 when Char.code s.[1] = 0x93 -> (* oe *)
          sprintf "%c%c%s" c (Char.chr 0x92)
            (String.sub s 2 (String.length s - 2))
      | 0xD0 when Char.code s.[1] >= 0xB0 -> (* cyrillic lowercase *)
          let c1 = Char.chr (Char.code s.[1] - 0xB0 + 0x90) in
          sprintf "%c%c%s" c c1 (String.sub s 2 (String.length s - 2))
      | 0xD1 when Char.code s.[1] < 0x90 -> (* cyrillic lowercase again *)
          let c1 = Char.chr (Char.code s.[1] - 0x80 + 0xA0) in
          sprintf "%c%c%s" (Char.chr 0xD0) c1
            (String.sub s 2 (String.length s - 2))
      | _ -> s ]
;

value index_of_next_char s i =
  if Mutil.utf_8_db.val then
    min (String.length s) (i + max 1 (Name.nbc s.[i]))
  else i + 1
;

value capitale s =
  if Mutil.utf_8_db.val then capitale_utf_8 s
  else capitale_iso_8859_1 s
;

type format2 'a 'b = format4 'a unit string 'b;

value fcapitale (a : format4 'a 'b 'c 'd) : format4 'a 'b 'c 'd =
  Obj.magic capitale a
;

value nth_field_abs w n =
  let rec start i n =
    if n = 0 then i
    else if i < String.length w then
      match w.[i] with
      [ '<' -> start (i + 2) n
      | '/' -> start (i + 1) (n - 1)
      | _ -> start (i + 1) n ]
    else i
  in
  let rec stop i =
    if i < String.length w then
      match w.[i] with
      [ '<' -> stop (i + 2)
      | '/' -> i
      | _ -> stop (i + 1) ]
    else i
  in
  let i1 = start 0 n in let i2 = stop i1 in (i1, i2)
;

value nth_field w n =
  let (i1, i2) = nth_field_abs w n in
  let (i1, i2) = if i2 = i1 then nth_field_abs w 0 else (i1, i2) in
  String.sub w i1 (i2 - i1)
;

value tnf s = "[" ^ s ^ "]";

value transl conf w =
  try Hashtbl.find conf.lexicon w with
  [ Not_found -> tnf w ]
;

value transl_nth conf w n =
  try nth_field (Hashtbl.find conf.lexicon w) n with
  [ Not_found -> tnf (nth_field w n) ]
;

value plus_decl s =
  match rindex s '+' with
  [ Some i ->
      if i > 0 && s.[i - 1] = ' ' then
        let start = String.sub s 0 (i - 1) in
        let decl = String.sub s (i - 1) (String.length s - (i - 1)) in
        Some (start, decl)
      else None
  | None -> None ]
;

value gen_decline wt s =
  let s1 = if s = "" then "" else if wt = "" then s else " " ^ s in
  let len = String.length wt in
  if rindex wt '/' <> None then
    match rindex wt '/' with
    [ Some i ->
        (* special case for Spanish *)
        if String.length s > 0 && start_with_hi_i s then
          nth_field wt 1 ^ Mutil.decline 'n' s
        else nth_field wt 0 ^ Mutil.decline 'n' s1
    | None -> wt ^ Mutil.decline 'n' s1 ]
  else if len >= 3 && wt.[len - 3] = ':' && wt.[len - 1] = ':' then
    let start = String.sub wt 0 (len - 3) in
    start ^ Mutil.decline wt.[len - 2] s
  else
    match plus_decl wt with
    [ Some (start, " +before") ->
        if s = "" then start else Mutil.decline 'n' s ^ " " ^ start
    | _ -> wt ^ Mutil.decline 'n' s1 ]
;

value transl_decline conf w s =
  Translate.eval (gen_decline (transl conf w) s)
;

value gen_decline2 wt s1 s2 =
  let string_of =
    fun
    [ '1' -> Some s1
    | '2' -> Some s2
    | _ -> None ]
  in
  let len = String.length wt in
  let rec loop i =
    if i = len then ""
    else
      let (s, i) =
        match wt.[i] with
        [ '%' when i + 1 < len ->
            match string_of wt.[i + 1] with
            [ Some s -> (s, i + 1)
            | None -> ("%", i) ]
        | ':' when i + 4 < len && wt.[i + 2] = ':' && wt.[i + 3] = '%' ->
            let c = wt.[i + 1] in
            match string_of wt.[i + 4] with
            [ Some s -> (decline c s, i + 4)
            | None -> (":", i) ]
        | '[' ->
            try
              let j = String.index_from wt i ']' in
              if j + 2 < len && wt.[j + 1] = '%' then
                match string_of wt.[j + 2] with
                [ Some s ->
                    let s =
                      if start_with_vowel s then String.make 1 wt.[j - 1] ^ s
                      else String.sub wt (i + 1) (j - i - 2) ^ " " ^ s
                    in
                    (s, j + 2)
                | None -> raise Not_found ]
              else raise Not_found
            with
            [ Not_found -> ("[", i) ]
        | c -> (String.make 1 c, i) ]
      in
      s ^ loop (i + 1)
  in
  (*surtout pas ! Translate.eval*) (loop 0)
;

value transl_a_of_b conf x y =
  gen_decline2 (transl_nth conf "%1 of %2" 0) x y
;
value transl_a_of_gr_eq_gen_lev conf x y =
  gen_decline2 (transl_nth conf "%1 of %2" 1) x y
;

value check_format ini_fmt (r : string) =
  let s : string = Obj.magic (ini_fmt : format4 'a 'b 'c 'd) in
  let rec loop i j =
    if i < String.length s - 1 && j < String.length r - 1 then
      match (s.[i], s.[i + 1], r.[j], r.[j + 1]) with
      [ ('%', x, '%', y) ->
          if x = y then loop (i + 2) (j + 2) else None
      | ('%', _, _, _) -> loop i (j + 1)
      | (_, _, '%', _) -> loop (i + 1) j
      | _ -> loop (i + 1) (j + 1) ]
    else if i < String.length s - 1 then
      if s.[i] = '%' then None else loop (i + 1) j
    else if j < String.length r - 1 then
      if r.[j] = '%' then None else loop i (j + 1)
    else
      Some (Obj.magic r : format4 'a 'b 'c 'd)
  in
  loop 0 0
;

value valid_format ini_fmt r =
  match check_format ini_fmt r with
  [ Some fmt -> fmt
  | None -> Obj.magic (tnf (Obj.magic ini_fmt)) ]
;

value cftransl conf fmt =
  let fmt = transl conf fmt in
  let rec loop i =
    fun
    [ [] -> String.sub fmt i (String.length fmt - i)
    | [a :: al] as gal ->
        if i + 4 < String.length fmt && fmt.[i] = ':' &&
           fmt.[i + 2] = ':' && fmt.[i + 3] = '%' && fmt.[i + 4] = 's' then
          decline fmt.[i + 1] a ^ loop (i + 5) al
        else if
          i + 1 < String.length fmt && fmt.[i] = '%' &&
          fmt.[i + 1] = 's' then
          nominative a ^ loop (i + 2) al
        else if i < String.length fmt then
          String.make 1 fmt.[i] ^ loop (i + 1) gal
        else "" ]
  in
  loop 0
;

value ftransl conf s = valid_format s (transl conf (Obj.magic s : string));

value ftransl_nth conf s p =
  valid_format s (transl_nth conf (Obj.magic s : string) p)
;

value fdecline conf w s =
  valid_format w (gen_decline (Obj.magic w : string) s)
;

value translate_eval s = Translate.eval (nominative s);

(* *)

value begin_centered conf =
  Wserver.wprint
    "<table border=\"%d\" width=\"100%%\"><tr><td align=\"center\">\n"
    conf.border;
value end_centered _ = Wserver.wprint "</td></tr></table>\n";

value html_br conf = Wserver.wprint "<br%s>\n" conf.xhs;

value html_p conf = do { Wserver.wprint "<p>"; Wserver.wprint "\n"; };

value html_li conf = do { Wserver.wprint "<li>"; Wserver.wprint "\n"; };

value nl () = Wserver.wprint "\013\010";

value week_day_txt =
  let txt = [| "Sun"; "Mon"; "Tue"; "Wed"; "Thu"; "Fri"; "Sat" |] in
  fun i ->
    let i = if i < 0 || i >= Array.length txt then 0 else i in
    txt.(i)
;
value month_txt =
  let txt =
    [| "Jan"; "Feb"; "Mar"; "Apr"; "May"; "Jun"; "Jul"; "Aug"; "Sep"; "Oct";
       "Nov"; "Dec" |]
  in
  fun i ->
    let i = if i < 0 || i >= Array.length txt then 0 else i in
    txt.(i)
;

value string_of_ctime conf =
  let lt = Unix.gmtime conf.ctime in
  sprintf "%s, %d %s %d %02d:%02d:%02d GMT"
    (week_day_txt lt.Unix.tm_wday) lt.Unix.tm_mday (month_txt lt.Unix.tm_mon)
    (1900 + lt.Unix.tm_year) lt.Unix.tm_hour lt.Unix.tm_min lt.Unix.tm_sec
;

value html conf =
  let charset = if conf.charset = "" then "utf-8" else conf.charset in
  do {
    if not conf.cgi then do {
      Wserver.http "";
      Wserver.wprint "Server: GeneWeb/%s" Version.txt;
      nl ();
    }
    else ();
    Wserver.wprint "Date: %s" (string_of_ctime conf); nl ();
    Wserver.wprint "Connection: close"; nl ();
    Wserver.wprint "Content-type: %s; charset=%s"
      (if conf.pure_xhtml then "application/xhtml+xml" else "text/html")
      charset;
    nl ();
  }
;

value unauthorized conf auth_type =
  do {
    if not conf.cgi then do {
      Wserver.http "401 Unauthorized";
      Wserver.wprint "WWW-Authenticate: Basic realm=\"%s\"" auth_type;
      nl ()
    }
    else ();
    Wserver.wprint "Content-type: text/html; charset=%s" conf.charset;
    nl ();
    nl ();
    Wserver.wprint "<head><title>Access failed</title></head>\n";
    Wserver.wprint "<body><h1>Access failed</h1>\n";
    Wserver.wprint "<ul><li>%s</ul>\n" auth_type;
    Wserver.wprint "</body>\n";
  }
;

value commd conf =
  let c = conf.command ^ "?" in
  List.fold_left (fun c (k, v) -> c ^ k ^ "=" ^ v ^ ";") c
    (conf.henv @ conf.senv)
;

value code_varenv = Wserver.encode;
value decode_varenv = Wserver.decode;

value quote_escaped s =
  let rec need_code i =
    if i < String.length s then
      match s.[i] with
      [ '"' | '&' | '<' | '>' -> True
      | x -> need_code (succ i) ]
    else False
  in
  let rec compute_len i i1 =
    if i < String.length s then
      let i1 =
        match s.[i] with
        [ '"' -> i1 + 6
        | '&' -> i1 + 5
        | '<' | '>' -> i1 + 4
        | _ -> succ i1 ]
      in
      compute_len (succ i) i1
    else i1
  in
  let rec copy_code_in s1 i i1 =
    if i < String.length s then
      let i1 =
        match s.[i] with
        [ '"' -> do { String.blit "&#034;" 0 s1 i1 6; i1 + 6 }
        | '&' -> do { String.blit "&amp;" 0 s1 i1 5; i1 + 5 }
        | '<' -> do { String.blit "&lt;" 0 s1 i1 4; i1 + 4 }
        | '>' -> do { String.blit "&gt;" 0 s1 i1 4; i1 + 4 }
        | c -> do { s1.[i1] := c; succ i1 } ]
      in
      copy_code_in s1 (succ i) i1
    else s1
  in
  if need_code 0 then
    let len = compute_len 0 0 in copy_code_in (String.create len) 0 0
  else s
;

value no_html_tags s =
  let rec need_code i =
    if i < String.length s then
      match s.[i] with
      [ '<' | '>' -> True
      | _ -> need_code (i + 1) ]
    else False
  in
  if need_code 0 then
    let rec loop i len =
      if i = String.length s then Buff.get len
      else
        let (len, next_i) =
          match s.[i] with
          [ '<' -> (Buff.mstore len "&lt;", i + 1)
          | '>' -> (Buff.mstore len "&gt;", i + 1)
          | c -> (Buff.store len c, i + 1) ]
        in
        loop next_i len
    in
    loop 0 0
  else s
;

value hidden_env conf =
  List.iter
    (fun (k, v) ->
       Wserver.wprint "<input type=\"hidden\" name=\"%s\" value=\"%s\"%s>\n" k
         (quote_escaped (decode_varenv v)) conf.xhs)
    (conf.henv @ conf.senv)
;

value p_getenv env label =
  try Some (decode_varenv (List.assoc (decode_varenv label) env)) with
  [ Not_found -> None ]
;

value p_getint env label =
  match p_getenv env label with
  [ Some s ->
      try Some (int_of_string (strip_spaces s)) with
      [ Failure _ -> None ]
  | None -> None ]
;

value nobtit conf base p =
  Gwdb.nobtit base conf.allowed_titles conf.denied_titles p
;

value is_old_person conf p =
  match
    (Adef.od_of_codate p.birth, Adef.od_of_codate p.baptism,
     p.death, CheckItem.date_of_death p.death)
  with
  [ (_, _, NotDead, _) when conf.private_years > 0 -> False
  | (Some (Dgreg d _), _, _, _) ->
      let a = CheckItem.time_elapsed d conf.today in
      a.year > conf.private_years
  | (_, Some (Dgreg d _), _, _) ->
      let a = CheckItem.time_elapsed d conf.today in
      a.year > conf.private_years
  | (_, _, _, Some (Dgreg d _)) ->
      let a = CheckItem.time_elapsed d conf.today in
      a.year > conf.private_years
  | (None, None, DontKnowIfDead, None) ->
      p.access <> Private && conf.public_if_no_date
  | _ -> False ]
;

value fast_auth_age conf p =
  if conf.friend || conf.wizard || get_access p = Public then True
  else if
    conf.public_if_titles && get_access p = IfTitles && get_titles p <> []
  then
    True
  else is_old_person conf (gen_person_of_person p)
;

value is_restricted (conf : config) base ip =
  let fct p =
    not (is_quest_string (get_surname p)) &&
    not (is_quest_string (get_first_name p)) &&
    not (fast_auth_age conf p)
  in  
  if conf.use_restrict then base_visible_get base fct (Adef.int_of_iper ip)
  else False 
;

value pget (conf : config) base ip =
  if is_restricted conf base ip then Gwdb.empty_person base ip
  else poi base ip
;

value parent_has_title conf base p =
  match get_parents p with
  [ Some ifam ->
      let cpl = foi base ifam in
      let fath = pget conf base (get_father cpl) in
      let moth = pget conf base (get_mother cpl) in
      get_access fath <> Private && nobtit conf base fath <> [] ||
      get_access moth <> Private && nobtit conf base moth <> []
  | _ -> False ]
;

value authorized_age conf base p =
  if conf.wizard || conf.friend || get_access p = Public then True
  else if
    conf.public_if_titles && get_access p = IfTitles &&
    (nobtit conf base p <> [] || parent_has_title conf base p) then
    True
  else
    match
      (Adef.od_of_codate (get_birth p), Adef.od_of_codate (get_baptism p),
       get_death p, CheckItem.date_of_death (get_death p))
    with
    [ (_, _, NotDead, _) when conf.private_years > 0 -> False
    | (Some (Dgreg d _), _, _, _) ->
        let a = CheckItem.time_elapsed d conf.today in
        a.year > conf.private_years
    | (_, Some (Dgreg d _), _, _) ->
        let a = CheckItem.time_elapsed d conf.today in
        a.year > conf.private_years
    | (_, _, _, Some (Dgreg d _)) ->
        let a = CheckItem.time_elapsed d conf.today in
        a.year > conf.private_years
    | (None, None, DontKnowIfDead, None) ->
        get_access p <> Private && conf.public_if_no_date
    | _ ->
        let rec loop i =
          if i >= Array.length (get_family p) then False
          else
            let fam = foi base (get_family p).(i) in
            match Adef.od_of_codate (get_marriage fam) with
            [ Some (Dgreg d _) ->
                let a = CheckItem.time_elapsed d conf.today in
                a.year > conf.private_years
            | _ -> loop (i + 1) ]
        in
        loop 0 ]
;

value is_hidden p = is_empty_string (get_surname p);

value know base p =
  sou base (get_first_name p) <> "?" || sou base (get_surname p) <> "?"
;

value is_public conf base p =
  get_access p = Public ||
  conf.public_if_titles && get_access p = IfTitles &&
    nobtit conf base p <> [] ||
  is_old_person conf (gen_person_of_person p)
;

value accessible_by_key conf base p fn sn =
  conf.access_by_key
  && not (fn = "?" || sn = "?")
  && (not conf.hide_names || is_public conf base p)
;

value acces_n conf base n x =
  let first_name = p_first_name base x in
  let surname = p_surname base x in
  if surname = "" then ""
  else if accessible_by_key conf base x first_name surname then
    "p" ^ n ^ "=" ^ code_varenv (Name.lower first_name) ^ ";n" ^ n ^ "=" ^
      code_varenv (Name.lower surname) ^
      (if get_occ x > 0 then ";oc" ^ n ^ "=" ^ string_of_int (get_occ x)
       else "")
  else
    "i" ^ n ^ "=" ^ string_of_int (Adef.int_of_iper (get_key_index x)) ^
    (if conf.wizard && get_occ x > 0 then
       ";oc" ^ n ^ "=" ^ string_of_int (get_occ x)
     else "")
;

value acces conf base x = acces_n conf base "" x;

type p_access = (base -> person -> string * base -> person -> string);
value std_access = (p_first_name, p_surname);
value raw_access =
  (fun base p -> sou base (get_first_name p),
   fun base p -> sou base (get_surname p))
;

value restricted_txt conf = ".....";

value gen_person_text (p_first_name, p_surname) conf base p =
  if is_hidden p then restricted_txt conf
  else if conf.hide_names && not (fast_auth_age conf p) then "x x"
  else
    let beg =
      match (sou base (get_public_name p), get_qualifiers p) with
      [ ("", [nn :: _]) ->
          p_first_name base p ^ " <em>" ^ sou base nn ^ "</em>"
      | ("", []) -> p_first_name base p
      | (n, [nn :: _]) -> n ^ " <em>" ^ sou base nn ^ "</em>"
      | (n, []) -> n ]
    in
(*
    let ali =
      match p.aliases with
      [ [alias :: _] -> " <em>(" ^ sou base alias ^ ")</em>"
      | _ -> "" ]
    in
*)
    beg ^ " " ^ p_surname base p (*^ ali*)
;

value gen_person_text_no_html (p_first_name, p_surname) conf base p =
  if is_hidden p then restricted_txt conf
  else if conf.hide_names && not (fast_auth_age conf p) then "x x"
  else
    let beg =
      match (sou base (get_public_name p), get_qualifiers p) with
      [ ("", [nn :: _]) -> p_first_name base p ^ " " ^ sou base nn
      | ("", []) -> p_first_name base p
      | (n, [nn :: _]) -> n ^ " " ^ sou base nn
      | (n, []) -> n ]
    in
    beg ^ " " ^ p_surname base p
;

value gen_person_text_without_surname check_acc (p_first_name, p_surname) conf
    base p
=
  if is_hidden p then restricted_txt conf
  else if check_acc && conf.hide_names && not (fast_auth_age conf p) then
    "x x"
  else
    let s =
      match (sou base (get_public_name p), get_qualifiers p) with
      [ (n, [nn :: _]) when n <> "" -> n ^ " <em>" ^ sou base nn ^ "</em>"
      | (n, []) when n <> "" -> n
      | (_, [nn :: _]) -> p_first_name base p ^ " <em>" ^ sou base nn ^ "</em>"
      | (_, []) -> p_first_name base p ]
    in
(*
    let ali =
      match p.aliases with
      [ [alias :: _] -> " <em>(" ^ sou base alias ^ ")</em>"
      | _ -> "" ]
    in
*)
    s (*^ ali*)
;

value person_text = gen_person_text std_access;
value person_text_no_html = gen_person_text_no_html std_access;
value person_text_without_surname =
  gen_person_text_without_surname True std_access
;
value person_text_no_surn_no_acc_chk =
  gen_person_text_without_surname False std_access
;

value main_title conf base p =
  let rec find_main =
    fun
    [ [] -> None
    | [x :: l] -> if x.t_name = Tmain then Some x else find_main l ]
  in
  match find_main (nobtit conf base p) with
  [ None ->
      match nobtit conf base p with
      [ [x :: _] -> Some x
      | _ -> None ]
  | x -> x ]
;

value titled_person_text conf base p t =
  let estate = sou base t.t_place in
  let surname = p_surname base p in
  let elen = String.length estate in
  let slen = String.length surname in
  if Name.strip_lower estate = Name.strip_lower surname then
    match (t.t_name, get_qualifiers p) with
    [ (Tname n, []) -> sou base n
    | (Tname n, [nn :: _]) -> sou base n ^ " <em>" ^ sou base nn ^ "</em>"
    | _ -> person_text_without_surname conf base p ]
  else if elen < slen && String.sub surname (slen - elen) elen = estate then
    match (t.t_name, get_qualifiers p) with
    [ (Tname n, []) -> sou base n
    | (Tname n, [nn :: _]) -> sou base n ^ " <em>" ^ sou base nn ^ "</em>"
    | _ ->
        let trunc_surname _ _ =
          strip_spaces (String.sub surname 0 (slen - elen))
        in
        let trunc_access = (p_first_name, trunc_surname) in
        gen_person_text trunc_access conf base p ]
  else
    match t.t_name with
    [ Tname s ->
        let s = sou base s in
        match get_qualifiers p with
        [ [] -> s
        | [nn :: _] -> s ^ " <em>" ^ sou base nn ^ "</em>" ]
    | _ -> person_text conf base p ]
;

value one_title_text conf base p t =
  let place = sou base t.t_place in
  let s = sou base t.t_ident in
  let s = if place = "" then s else s ^ " " ^ place in ", <em>" ^ s ^ "</em>"
;

value geneweb_link conf href s =
  if conf.cancel_links then s
  else "<a href=\"" ^ commd conf ^ href ^ "\">" ^ s ^ "</a>"
;

value wprint_geneweb_link conf href s =
  Wserver.wprint "%s" (geneweb_link conf href s)
;

value reference conf base p s =
  if conf.cancel_links || is_hidden p then s
  else "<a href=\"" ^ commd conf ^ acces conf base p ^ "\">" ^ s ^ "</a>"
;

value no_reference conf base p s = s;

value gen_person_title_text reference p_access conf base p =
  if authorized_age conf base p then
    match main_title conf base p with
    [ Some t ->
        reference conf base p (titled_person_text conf base p t) ^
          one_title_text conf base p t
    | None -> reference conf base p (gen_person_text p_access conf base p) ]
  else reference conf base p (gen_person_text p_access conf base p)
;

value referenced_person_title_text =
  gen_person_title_text reference std_access
;

value person_title_text = gen_person_title_text no_reference std_access;

value referenced_person_text conf base p =
  reference conf base p (person_text conf base p)
;

value referenced_person_text_without_surname conf base p =
  reference conf base p (person_text_without_surname conf base p)
;

value gen_person_text_without_title p_access conf base p =
  match main_title conf base p with
  [ Some t ->
      if eq_istr t.t_place (get_surname p) then
        gen_person_text_without_surname True p_access conf base p
      else
        match (t.t_name, get_qualifiers p) with
        [ (Tname s, [nn :: _]) -> sou base s ^ " <em>" ^ sou base nn ^ "</em>"
        | (Tname s, _) -> sou base s
        | _ -> gen_person_text p_access conf base p ]
  | None -> gen_person_text p_access conf base p ]
;

value person_text_without_title = gen_person_text_without_title std_access;

value person_title conf base p =
  if authorized_age conf base p then
    match main_title conf base p with
    [ Some t -> one_title_text conf base p t
    | None -> "" ]
  else ""
;

value old_surname_begin n =
  let i = initial n in
  if i = 0 then ""
  else
    let i =
      strip_spaces i where rec strip_spaces i =
        if i >= 1 && n.[i - 1] = ' ' then strip_spaces (pred i) else i
    in
    " (" ^ String.sub n 0 i ^ ")"
;

value old_surname_end n =
  let i = initial n in
  if i = 0 then n else String.sub n i (String.length n - i)
;

value start_with s i p =
  i + String.length p <= String.length s &&
  String.lowercase (String.sub s i (String.length p)) = p
;

value start_with2 s i p =
  i + String.length p <= String.length s &&
  String.sub s i (String.length p) = p
;

value get_particle base s =
  loop (base_particles base) where rec loop =
    fun
    [ [part :: parts] -> if start_with2 s 0 part then part else loop parts
    | [] -> "" ]
;

value surname_begin base s =
  let part = get_particle base s in
  let len = String.length part in
  if len = 0 then ""
  else if part.[len-1] = ' ' then " (" ^ String.sub part 0 (len - 1) ^ ")"
  else " (" ^ part ^ ")"
;

value surname_end base s =
  let part_len = String.length (get_particle base s) in
  String.sub s part_len (String.length s - part_len)
;

value rec skip_spaces s i =
  if i < String.length s && s.[i] = ' ' then skip_spaces s (i + 1) else i
;

value create_env s =
  let rec get_assoc beg i =
    if i = String.length s then
      if i = beg then [] else [String.sub s beg (i - beg)]
    else if s.[i] = ';' || s.[i] = '&' then
      let next_i = skip_spaces s (succ i) in
      [String.sub s beg (i - beg) :: get_assoc next_i next_i]
    else get_assoc beg (succ i)
  in
  let rec separate i s =
    if i = String.length s then (s, "")
    else if s.[i] = '=' then
      (String.sub s 0 i, String.sub s (succ i) (String.length s - succ i))
    else separate (succ i) s
  in
  List.map (separate 0) (get_assoc 0 0)
;

value std_color conf s =
  "<span style=\"color:" ^ conf.highlight ^ "\">" ^ s ^ "</span>"
;

value index_of_sex =
  fun
  [ Male -> 0
  | Female -> 1
  | Neuter -> 2 ]
;

value input_to_semi ic =
  loop 0 where rec loop len =
    let c = input_char ic in
    if c = ';' then Buff.get len else loop (Buff.store len c)
;

value base_path pref bname =
  let pref = [Secure.base_dir () :: pref] in
  let bfile = List.fold_right Filename.concat pref bname in
  IFDEF WIN95 THEN bfile
  ELSE if Sys.file_exists bfile then bfile
  else if String.length bname >= 6 then
    let dirs = pref @ [String.make 1 bname.[0]; String.make 1 bname.[1]] in
    List.fold_right Filename.concat dirs bname
  else bfile
  END
;

value base_len n =
  let n = base_path [] (n ^ ".gwb") in
  match
    try Some (Gwdb.open_base n) with [ Sys_error _ -> None ]
  with
  [ Some base ->
      let len = nb_of_persons base in
      do { close_base base; string_of_int len }
  | _ -> "?" ]
;

value open_etc_file fname =
  let fname1 = base_path ["etc"] (Filename.basename fname ^ ".txt") in
  let fname2 =
    search_in_lang_path
      (Filename.concat "etc" (Filename.basename fname ^ ".txt"))
  in
  try Some (Secure.open_in fname1) with
  [ Sys_error _ ->
      try Some (Secure.open_in fname2) with [ Sys_error _ -> None ] ]
;

value macro_etc env imcom c =
  try List.assoc c env () with
  [ Not_found ->
      match c with
      [ '%' -> "%"
      | 'k' -> imcom
      | 'o' ->
          if images_url.val <> "" then images_url.val else imcom ^ "m=IM;v="
      | 'v' -> Version.txt
      | '/' -> ""
      | c -> "%" ^ String.make 1 c ] ]
;

(* "copy_from_etc" is old method; rather use "Templ.copy_from_templ" *)
value rec copy_from_etc env lang imcom ic =
  let cnt = ref 0 in
  try
    while True do {
      match input_char ic with
      [ '%' ->
          let c = input_char ic in
          match c with 
          [ '+' -> incr cnt
          | '#' -> Wserver.wprint "%d" cnt.val
          | 'n' -> Wserver.wprint "%s" (base_len (input_to_semi ic))
          | 'r' ->
              let name = input_line ic in
              match open_etc_file name with
              [ Some ic -> copy_from_etc env lang imcom ic
              | None ->
                  Wserver.wprint
                    "<em>... file not found: \"%s.txt\"</em><br>" name ]
          | c -> Wserver.wprint "%s" (macro_etc env imcom c) ]
      | '[' ->
          let c = input_char ic in
          if c = '\n' then
            let s =
              loop 0 (input_char ic) where rec loop len c =
                if c = ']' then Buff.get len
                else loop (Buff.store len c) (input_char ic)
            in
            let (s, alt) = Translate.inline lang '%' (macro_etc env imcom) s in
            let s = if alt then tnf s else s in
            Wserver.wprint "%s" s
          else
            Wserver.wprint "[%c" c
      | c -> Wserver.wprint "%c" c ]
    }
  with exc ->
    do {
      close_in ic;
      match exc with
      [ End_of_file -> ()
      | exc -> raise exc ]
    }
;

value image_prefix conf =
  if images_url.val <> "" then images_url.val
  else if conf.cgi then conf.command ^ "?m=IM;v="
  else "images"
;

value default_background conf =
  sprintf "background:url('%s/gwback.jpg')" (image_prefix conf)
;

value default_body_prop conf =
  let style =
    match p_getenv conf.env "size" with
    [ Some v -> "font-size:" ^ v ^ ";"
    | None -> "" ]
  in
  let style = sprintf "%s%s" style (default_background conf) in
  " style=\"" ^ style ^ "\""
;

value body_prop conf =
  try
    match List.assoc "body_prop" conf.base_env with
    [ "" -> default_body_prop conf
    | s -> " " ^ s ]
  with
  [ Not_found -> default_body_prop conf ]
;

value get_server_string_aux cgi request =
  if not cgi then Wserver.extract_param "host: " '\r' request
  else
    let server_name = try Sys.getenv "SERVER_NAME" with [ Not_found -> "" ] in
    let server_port =
      try Sys.getenv "SERVER_PORT" with [ Not_found | Failure _ -> "80" ]
    in
    if server_port = "80" then server_name
    else server_name ^ ":" ^ server_port
;

value get_request_string_aux cgi request =
  if not cgi then Wserver.extract_param "GET " ' ' request
  else
    let script_name = try Sys.getenv "SCRIPT_NAME" with [ Not_found -> "" ] in
    let query_string =
      try Sys.getenv "QUERY_STRING" with [ Not_found -> "" ]
    in
    script_name ^ "?" ^ query_string
;

value get_server_string conf = get_server_string_aux conf.cgi conf.request;
value get_request_string conf = get_request_string_aux conf.cgi conf.request;

value url_no_index conf base =
  let scratch s = code_varenv (Name.lower (sou base s)) in
  let get_a_person v =
    match try Some (int_of_string v) with [ Failure _ -> None ] with
    [ Some i ->
        if i >= 0 && i < nb_of_persons base then
          let p = pget conf base (Adef.iper_of_int i) in
          if (conf.hide_names && not (fast_auth_age conf p)) || is_hidden p
          then None
          else
            let f = scratch (get_first_name p) in
            let s = scratch (get_surname p) in
            let oc = string_of_int (get_occ p) in
            Some (f, s, oc)
        else None
    | None -> None ]
  in
  let get_a_family v =
    match try Some (int_of_string v) with [ Failure _ -> None ] with
    [ Some i ->
        if i >= 0 && i < nb_of_families base then
          let fam = foi base (Adef.ifam_of_int i) in
          if is_deleted_family fam then None
          else
            let p = pget conf base (get_father fam) in
            let f = scratch (get_first_name p) in
            let s = scratch (get_surname p) in
            if f = "" || s = "" then None
            else
              let oc = string_of_int (get_occ p) in
              let u = pget conf base (get_father fam) in
              let n =
                loop 0 where rec loop k =
                  if (get_family u).(k) = Adef.ifam_of_int i then
                    string_of_int k
                  else loop (k + 1)
              in
              Some (f, s, oc, n)
        else None
    | None -> None ]
  in
  let env =
    let rec loop =
      fun
      [ [] -> []
      | [("opt", "no_index") :: l] -> loop l
      | [("dsrc" | "escache" | "oc" | "templ", _) :: l] -> loop l
      | [("i", v) :: l] -> new_env "i" v (fun x -> x) l
      | [("ei", v) :: l] -> new_env "ei" v (fun x -> "e" ^ x) l
      | [(k, v) :: l] when String.length k = 2 && k.[0] = 'i' ->
          let c = String.make 1 k.[1] in new_env k v (fun x -> x ^ c) l
      | [(k, v) :: l]
        when String.length k > 2 && k.[0] = 'e' && k.[1] = 'f' ->
          new_fam_env k v (fun x -> x ^ k) l
      | [kv :: l] -> [kv :: loop l] ]
    and new_env k v c l =
      match get_a_person v with
      [ Some (f, s, oc) ->
          if oc = "0" then [(c "p", f); (c "n", s) :: loop l]
          else [(c "p", f); (c "n", s); (c "oc", oc) :: loop l]
      | None -> [(k, v) :: loop l] ]
    and new_fam_env k v c l =
      match get_a_family v with
      [ Some (f, s, oc, n) ->
          let l = loop l in
          let l = if n = "0" then l else [(c "f", n) :: l] in
          if oc = "0" then [(c "p", f); (c "n", s) :: l]
          else [(c "p", f); (c "n", s); (c "oc", oc) :: l]
      | None -> [(k, v) :: loop l] ]
    in
    loop conf.env
  in
  let addr =
    let pref =
      let s = get_request_string conf in
      match rindex s '?' with
      [ Some i -> String.sub s 0 i
      | None -> s ]
    in
    get_server_string conf ^ pref
  in
  let suff =
    List.fold_right
      (fun (x, v) s ->
         let sep = if s = "" then "" else ";" in x ^ "=" ^ v ^ sep ^ s)
      [("lang", conf.lang) :: env] ""
  in
  let suff = if conf.cgi then "b=" ^ conf.bname ^ ";" ^ suff else suff in
  addr ^ "?" ^ suff
;

value message_to_wizard conf =
  if conf.wizard || conf.just_friend_wizard then
    let print_file fname =
      let fname = base_path ["etc"; conf.bname] (fname ^ ".txt") in
      match try Some (Secure.open_in fname) with [ Sys_error _ -> None ] with
      [ Some ic ->
          try while True do { Wserver.wprint "%c" (input_char ic); } with
          [ End_of_file -> close_in ic ]
      | None -> () ]
    in
    do {
      print_file "mess_wizard";
      if conf.user <> "" then
        print_file ("mess_wizard_" ^ conf.user)
      else ();
    }
  else ()
;

value doctype conf =
  match p_getenv conf.base_env "doctype" with
  [ Some "html-4.01-trans" -> "\
<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\"
 \"http://www.w3.org/TR/html4/loose.dtd\">"
  | Some "html-4.01" -> "\
<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\"
 \"http://www.w3.org/TR/html4/strict.dtd\">"
  | Some "xhtml-1.0-trans" -> "\
<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\"
 \"http://www.w3.org/TR/xhtml10/DTD/loose.dtd\">"
  | _ -> "\
<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.1//EN\" 
 \"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd\">" ]
;

value http_string conf s i =
  let http = "http://" in
  if start_with s i http then
    let j =
      loop (i + String.length http) where rec loop j =
        if j < String.length s then
          match s.[j] with
          [ 'a'..'z' | 'A'..'Z' | '\128' .. '\255' | '0'..'9' | '!' | '#' |
            '$' | '%' | '&' | '(' | ')' | '*' | '+' | ',' | '-' | '.' | '/' |
            ':' | ';' | '=' | '?' | '@' | '\\' | '_' | '~' -> loop (j + 1)
          | '[' | '^' | '{' | '|' -> j + 1
          | ']' | '}' -> j
          | _ -> j ]
        else j
    in
    let j =
      match s.[j - 1] with
      [ ')' | ',' |  '.' |  ':' | ';' -> j - 1
      | _ -> j ]
    in
    let s = String.sub s i (j - i) in
    Some (s, j)
  else None
;

value rec followed_by_ident_semi s i =
  if i = String.length s then False
  else
    match s.[i] with
    [ 'a'..'z' | 'A'..'Z' -> followed_by_ident_semi s (i + 1)
    | '#' | '0'..'9' -> followed_by_ident_semi s (i + 1)
    | ';' -> True
    | _ -> False ]
;

value expand_ampersand buff s =
  loop 0 where rec loop i =
    if i = String.length s then ()
    else do {
      if s.[i] = '&' then Buffer.add_string buff "&amp;"
      else Buffer.add_char buff s.[i];
      loop (i + 1)
    }
;

value email_addr s i =
  let rec before_at empty i =
    if i = String.length s then None
    else
      match s.[i] with
      [ 'a'..'z' | 'A'..'Z' | '0'..'9' | '-' | '_' | '.' ->
          before_at False (i + 1)
      | '@' -> if empty then None else after_at True (i + 1)
      | _ -> None ]
  and after_at empty i =
    if i = String.length s then None
    else
      match s.[i] with
      [ 'a'..'z' | 'A'..'Z' | '0'..'9' | '-' | '_' -> after_at False (i + 1)
      | '.' -> if empty then None else after_dot 0 (i + 1)
      | _ -> None ]
  and after_dot len i =
    if i = String.length s then Some (len, i)
    else
      match s.[i] with
      [ 'a'..'z' | 'A'..'Z' | '0'..'9' | '-' | '_' | '.' ->
          after_dot (len + 1) (i + 1)
      | _ -> Some (len, i) ]
  in
  match before_at True i with
  [ Some (len, i) ->
      let (len, i) =
        if len > 0 && s.[i - 1] = '.' then (len - 1, i - 1) else (len, i)
      in
      if len = 0 then None else Some i
  | None -> None ]
;

value tag_id s i =
  loop i 0 where rec loop i len =
    if i = String.length s then Buff.get len
    else
      match s.[i] with
      [ 'a'..'z' | 'A'..'Z' | '0'..'9' | '!' | '-' ->
          loop (i + 1) (Buff.store len (Char.lowercase s.[i]))
      | _ -> if len = 0 then loop (i + 1) 0 else Buff.get len ]
;

value default_good_tag_list =
  ["a"; "b"; "blockquote"; "br"; "center"; "cite"; "dd"; "dir"; "div"; "dl";
   "dt"; "em"; "font"; "hr"; "h1"; "h2"; "h3"; "h4"; "h5"; "h6"; "i"; "img";
   "li"; "ol"; "p"; "pre"; "span"; "strong"; "sub"; "sup"; "table"; "tbody";
   "td"; "th"; "tr"; "tt"; "u"; "ul"; "!--"]
;

value allowed_tags_file = ref "";

value good_tag_list_fun () =
  if allowed_tags_file.val <> "" then
    match
      try Some (open_in allowed_tags_file.val) with [ Sys_error _ -> None ]
    with
    [ Some ic ->
        loop [] where rec loop tags =
          match try Some (input_line ic) with [ End_of_file -> None ] with
          [ Some tg -> loop [String.lowercase tg :: tags]
          | None -> do { close_in ic; tags } ]
    | None -> default_good_tag_list ]
  else default_good_tag_list
;

value good_tags_list = Lazy.lazy_from_fun good_tag_list_fun;
value good_tag s i = List.mem (tag_id s i) (Lazy.force good_tags_list);

module Lbuff = Buff.Make (struct value buff = ref (String.create 80); end);

value filter_html_tags s =
  loop 0 0 where rec loop len i =
    if i < String.length s then
      if s.[i] = '<' && not (good_tag s (i + 1)) then
        loop (Lbuff.mstore len "&lt;") (i + 1)
      else loop (Lbuff.store len s.[i]) (i + 1)
    else Lbuff.get len
;

value get_variable s i =
  loop 0 i where rec loop len i =
    if i = String.length s then (Buff.get len, [], i)
    else
      match s.[i] with
      [ 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' as c ->
          loop (Buff.store len c) (i + 1)
      | ':' ->
          let v = Buff.get len in
          loop [] 0 (i + 1) where rec loop vl len i =
            if i = String.length s then (v, List.rev [Buff.get len :: vl], i)
            else
              match s.[i] with
              [ ':' -> loop [Buff.get len :: vl] 0 (i + 1)
              | ';' -> (v, List.rev [Buff.get len :: vl], i + 1)
              | c -> loop vl (Buff.store len c) (i + 1) ]
      | ';' -> (Buff.get len, [], i + 1)
      | _ -> (Buff.get len, [], i) ]
;

type tag_type = [ In_a_href | In_norm | Out ];

value expand_env =
  let buff = Buffer.create 30 in
  fun conf s ->
    match p_getenv conf.base_env "expand_env" with
    [ Some "yes" ->
        let _ : unit = Buffer.clear buff in
        loop 0 where rec loop i =
          if i = String.length s then Buffer.contents buff
          else if i + 1 < String.length s && s.[i] = '$' && s.[i+1] = '{' then
            try
              let j = String.index_from s (i+1) '}' in
              let v = Sys.getenv (String.sub s (i + 2) (j - i - 2)) in
              do { Buffer.add_string buff v; loop (j + 1) }
            with
            [ Not_found -> do { Buffer.add_char buff s.[i]; loop (i + 1) } ]
          else
            do { Buffer.add_char buff s.[i]; loop (i + 1) }
   | _ -> s ]
;

value string_with_macros conf env s =
  let buff = Buffer.create 1000 in
  loop Out 0 where rec loop tt i =
    if i < String.length s then
      if i + 1 < String.length s && s.[i] = '%' then
        let i =
          try
            do { Buffer.add_string buff (List.assoc s.[i + 1] env ()); i + 2 }
          with
          [ Not_found ->
              match s.[i + 1] with
              [ 's' -> do { Buffer.add_string buff (commd conf); i + 2 }
              | 'v' ->
                  let (k, vl, j) = get_variable s (i + 2) in
                  let (v, i) =
                    let v =
                      try
                        let v = List.assoc ("var_" ^ k) conf.base_env in
                        Some (expand_env conf v)
                      with
                      [ Not_found -> None ]
                    in
                    match v with
                    [ Some s ->
                        let s =
                          loop vl 0 0 where rec loop vl len i =
                            if i = String.length s then Buff.get len
                            else if
                              i + 1 < String.length s && s.[i] = '%' &&
                              s.[i+1] = 's'
                            then
                              match vl with
                              [ [v :: vl] ->
                                  loop vl (Buff.mstore len v) (i + 2)
                              | [] ->
                                  Buff.get len ^
                                    String.sub s i (String.length s - i) ]
                            else
                              loop vl (Buff.store len s.[i]) (i + 1)
                        in
                        (s, j)
                    | None -> ("%", i + 1) ]
                  in
                  do { Buffer.add_string buff v; i }
              | '%' -> do { Buffer.add_string buff "%"; i + 2 }
              | _ -> do { Buffer.add_string buff "%"; i + 1 } ] ]
        in
        loop tt i
      else
        match tt with
        [ In_a_href ->
            let tt = if start_with s i "</a>" then Out else In_a_href in
            do { Buffer.add_char buff s.[i]; loop tt (i + 1) }
        | In_norm ->
            let tt = if s.[i] = '>' then Out else In_norm in
            do { Buffer.add_char buff s.[i]; loop tt (i + 1) }
        | Out ->
            match http_string conf s i with
            [ Some (x, j) ->
                do {
                  bprintf buff "<a href=\"%s\">" x;
                  expand_ampersand buff x;
                  bprintf buff "</a>";
                  loop Out j
                }
            | None ->
                match email_addr s i with
                [ Some j ->
                    let x = String.sub s i (j - i) in
                    do {
                      bprintf buff "<a href=\"mailto:%s\">%s</a>" x x;
                      loop Out j
                    }
                | None ->
                    let tt =
                      if start_with s i "<a href=" ||
                         start_with s i "<a\nhref=" then
                        In_a_href
                      else if s.[i] = '<' then In_norm
                      else Out
                    in
                    do {
                      if s.[i] = '&' &&
                      not (followed_by_ident_semi s (i + 1)) then
                        Buffer.add_string buff "&amp;"
                      else
                        Buffer.add_char buff s.[i];
                      loop tt (i + 1)
                    } ] ] ]
    else filter_html_tags (Buffer.contents buff)
;

type xhtml_tag =
  [ Btag of string and string
  | Etag of string
  | Atag of string ]
;

value tag_params_ok s =
  loop 0 where rec loop i =
    if i = String.length s then True
    else
      match s.[i] with
      [ ' ' | '\n' -> loop (i+1)
      | 'a'..'z' ->
          loop_id (i+1) where rec loop_id i =
            if i = String.length s then False
            else
              match s.[i] with
              [ 'a'..'z' -> loop_id (i+1)
              | '=' ->
                  let i = i + 1 in
                  if i = String.length s then False
                  else if s.[i] = '"' then
                    loop_str (i+1) where rec loop_str i =
                      if i = String.length s then False
                      else if s.[i] = '"' then loop (i+1)
                      else loop_str (i+1)
                  else False
              | _ -> False ]
      | _ -> False ]
;

value xhtml_tag s i =
  if s.[i] = '<' then
    if i = String.length s - 1 then None
    else if s.[i+1] = '!' then None
    else
      let k =
        try String.index_from s i '>' with [ Not_found -> String.length s ]
      in
      let j =
        loop i where rec loop i =
          if i = k then k
          else
            match s.[i] with
            [ ' ' | '\n' -> i
            | _ -> loop (i + 1) ]
      in
      if i + 1 = String.length s then None
      else
        let next_i = min (k + 1) (String.length s) in
        if s.[i+1] = '/' then
          let t = String.sub s (i + 2) (k - i - 2) in
          if j = k then Some (Etag t, next_i) else None
        else if s.[k-1] = '/' then
          let t = String.sub s (i + 1) (k - i - 2) in
          Some (Atag t, next_i)
        else
          let t = String.sub s (i + 1) (j - i - 1) in
          let a = String.sub s j (k - j) in
          if tag_params_ok a then Some (Btag t a, next_i)
          else None
  else None
;

value check_ampersand s i =
  if i = String.length s then Some ("&amp;", i)
  else
    match s.[i] with
    [ 'a'..'z' ->
        loop_id i where rec loop_id j =
          if j = String.length s then do {
            let a = sprintf "&amp;%s" (String.sub s i (j - i)) in
            Some (a, j)
          }
          else
            match s.[j] with
            [ 'a'..'z' -> loop_id (j + 1)
            | ';' -> None
            | _ ->
                let a = sprintf "&amp;%s" (String.sub s i (j - i)) in
                Some (a, j) ]
    | _ -> Some ("&amp;", i) ]
;

value bad col s = sprintf "<span style=\"color:%s\">%s</span>" col s;

value check_ampersands s =
  let b = Buffer.create (String.length s) in
  loop False 0 where rec loop error i =
    if i = String.length s then
      if error then Some (Buffer.contents b)
      else None
    else
      match s.[i] with
      [ '&' ->
          match check_ampersand s (i + 1) with
          [ Some (txt, j) -> do {
              Buffer.add_string b (bad "red" txt);
              loop True j
            }
          | None -> do {
              Buffer.add_char b '&';
              loop error (i + 1)
            } ]
      | c -> do {
          Buffer.add_char b c;
          loop error (i + 1)
        } ]
;

value check_xhtml s =
  let b = Buffer.create (String.length s) in
  loop [] 0 where rec loop tag_stack i =
    if i = String.length s then do {
      List.iter
        (fun (pos, txt, t) -> do {
           let s = Buffer.contents b in
           let s_bef = String.sub s 0 pos in
           let pos_aft = pos + String.length txt + 2 in
           let s_aft = String.sub s pos_aft (String.length s - pos_aft) in
           Buffer.clear b;
           Buffer.add_string b s_bef;
           Buffer.add_string b (bad "red" (sprintf "&lt;%s&gt;" txt));
           Buffer.add_string b s_aft
         })
        tag_stack;
      Buffer.contents b
    }
    else
      match xhtml_tag s i with
      [ Some (Btag t a, i) ->
          if t = "br" && a = "" then do {
            (* frequent error *)
            Buffer.add_string b (sprintf "<%s/>" t);
            loop tag_stack i
          }
          else do {
            match check_ampersands a with
            [ Some a -> do {
                Buffer.add_string b (sprintf "&lt;%s%s&gt;" t a);
                loop tag_stack i;
              }
            | None -> do {
                let pos = Buffer.length b in
                let txt = sprintf "%s%s" t a in
                Buffer.add_string b (sprintf "<%s>" txt);
                loop [(pos, txt, t) :: tag_stack] i
              } ]
          }
      | Some (Etag t, i) ->
          match tag_stack with
          [ [(_, _, bt) :: rest] when t = bt -> do {
              Buffer.add_string b (sprintf "</%s>" t);
              loop rest i
            }
          | _ -> do {
              Buffer.add_string b (bad "red" (sprintf "&lt;/%s&gt;" t));
              loop tag_stack i
            } ]
      | Some (Atag t, i) -> do {
          Buffer.add_string b (sprintf "<%s/>" t);
          loop tag_stack i
        }
      | None ->
          if s.[i] = '&' then
            match check_ampersand s (i + 1) with
            [ Some (txt, j) -> do {
                Buffer.add_string b (bad "red" txt);
                loop tag_stack j
              }
            | None -> do {
                Buffer.add_char b '&';
                loop tag_stack (i + 1)
              } ]
          else do {
            if s.[i] = '<' && (i + 1 = String.length s || s.[i+1] <> '!')
            then
              Buffer.add_string b (bad "red" "&lt;")
            else Buffer.add_char b s.[i];
            loop tag_stack (i + 1)
          } ]
;

value compilation_time_hook = ref (fun _ -> "");
value compilation_time conf =
  match p_getenv conf.base_env "display_compilation_time" with
  [ Some "on" -> compilation_time_hook.val conf
  | _ -> "" ]
;

value menu_threshold = 20;

value is_number t =
  match t.[0] with
  [ '1'..'9' -> True
  | _ -> False ]
;

value hexa_string s =
  let s' = String.create (2 * String.length s) in
  do {
    for i = 0 to String.length s - 1 do {
      s'.[2*i] := "0123456789ABCDEF".[Char.code s.[i] / 16];
      s'.[2*i+1] := "0123456789ABCDEF".[Char.code s.[i] mod 16];
    };
    s'
  }
;

value print_alphab_list conf crit print_elem liste = do {
  let len = List.length liste in
  if len > menu_threshold then
    tag "p" begin
      let _ =
        List.fold_left
          (fun last e ->
             let t = crit e in
             let same_than_last =
               match last with
               [ Some t1 -> t = t1
               | _ -> False ]
             in
             do {
               if not same_than_last then
                 Wserver.wprint "<a href=\"#i%s\">%s</a>\n" (hexa_string t) t
               else ();
               Some t
             })
          None liste
      in
      ();
    end
  else ();
  tag "ul" begin
    let _ =
      List.fold_left
        (fun last e -> do {
           let t = crit e in
           let same_than_last =
             match last with
             [ Some t1 -> t = t1
             | _ -> False ]
           in
           if len > menu_threshold || is_number t then do {
             match last with
             [ Some _ ->
                 if not same_than_last then Wserver.wprint "</ul>\n</li>\n"
                 else ()
             | _ -> () ];
             if not same_than_last then do {
               Wserver.wprint "<li>\n";
               Wserver.wprint "<a id=\"i%s\">%s</a>\n" (hexa_string t) t;
               Wserver.wprint "<ul>\n";
             }
             else ();
           }
           else ();
           Wserver.wprint "<li>\n  ";
           print_elem e;
           Wserver.wprint "</li>\n";
           Some t
         })
        None liste
    in
    ();
    if len > menu_threshold then Wserver.wprint "</ul>\n</li>\n" else ();
  end;
};

value parent conf base p a =
  match get_public_name a with
  [ n when sou base n <> "" -> sou base n ^ person_title conf base a
  | _ ->
      if conf.hide_names && not (fast_auth_age conf a) then "x x"
      else
        p_first_name base a ^
          (if not (eq_istr (get_surname p) (get_surname a)) then
             " " ^ p_surname base a
           else "") ]
;

value print_parent conf base p fath moth =
  let s =
    match (fath, moth) with
    [ (Some fath, None) -> parent conf base p fath
    | (None, Some moth) -> parent conf base p moth
    | (Some fath, Some moth) ->
        parent conf base p fath ^ " " ^ transl_nth conf "and" 0 ^ " " ^
          parent conf base p moth
    | _ -> "" ]
  in
  let is = index_of_sex (get_sex p) in
  Wserver.wprint "%s"
    (translate_eval
      (transl_a_of_gr_eq_gen_lev conf
         (transl_nth conf "son/daughter/child" is) s))
;

value specify_homonymous conf base p =
  let is = index_of_sex (get_sex p) in
  match (get_public_name p, get_qualifiers p) with
  [ (n, [nn :: _]) when sou base n <> "" ->
      Wserver.wprint "%s <em>%s</em>" (sou base n) (sou base nn)
  | (_, [nn :: _]) ->
      Wserver.wprint "%s <em>%s</em>" (p_first_name base p) (sou base nn)
  | (n, []) when sou base n <> "" -> Wserver.wprint "%s" (sou base n)
  | (_, []) ->
      let a = pget conf base (get_key_index p) in
      let ifam =
        match get_parents a with
        [ Some ifam ->
            let cpl = foi base ifam in
            let fath =
              let fath = pget conf base (get_father cpl) in
              if p_first_name base fath = "?" then None else Some fath
            in
            let moth =
              let moth = pget conf base (get_mother cpl) in
              if p_first_name base moth = "?" then None else Some moth
            in
            Some (fath, moth)
        | None -> None ]
      in
      match ifam with
      [ Some (None, None) | None ->
          let rec loop i =
            if i < Array.length (get_family p) then
              let fam = foi base (get_family p).(i) in
              let conjoint = spouse (get_key_index p) fam in
              let ct = get_children fam in
              if Array.length ct > 0 then
                let enfant = pget conf base ct.(0) in
                let (child_fn, child_sn) =
                  if conf.hide_names && not (fast_auth_age conf enfant) then
                    ("x", " x")
                  else
                    (p_first_name base enfant,
                     if not (eq_istr (get_surname p) (get_surname enfant))
                     then
                       " " ^ p_surname base enfant
                     else "")
                in
                Wserver.wprint "%s"
                  (translate_eval
                     (transl_a_of_b conf
                        (transl_nth conf "father/mother" is)
                        (child_fn ^ child_sn)))
              else
                let conjoint = pget conf base conjoint in
                if p_first_name base conjoint <> "?" ||
                   p_surname base conjoint <> "?" then
                  Wserver.wprint "%s"
                    (translate_eval
                       (transl_a_of_b conf
                          (transl_nth conf "husband/wife" is)
                          (p_first_name base conjoint ^ " " ^
                           p_surname base conjoint)))
                else loop (i + 1)
            else Wserver.wprint "..."
          in
          loop 0
      | Some (fath, moth) -> print_parent conf base p fath moth ] ]
;

(* fix system bug: string_of_float 17.97 = "17.969999999999" *)
value my_string_of_float f = sprintf "%.6g" f;

value string_of_decimal_num conf f =
  let s = my_string_of_float f in
  let b = Buffer.create 20 in
  let rec loop i =
    if i = String.length s then Buffer.contents b
    else do {
      match s.[i] with
      [ '.' ->
          if i = String.length s - 1 then ()
          else Buffer.add_string b (transl conf "(decimal separator)")
      | x -> Buffer.add_char b x ];
      loop (i + 1)
    }
  in
  loop 0
;

value personal_image_file_name bname str =
  Filename.concat (base_path ["images"] bname) str
;

value source_image_file_name bname str =
  let fname1 =
    List.fold_right Filename.concat [base_path ["src"] bname; "images"] str
  in
  let fname2 =
    List.fold_right Filename.concat [Secure.base_dir (); "src"; "images"] str
  in
  if Sys.file_exists fname1 then fname1 else fname2
;

value image_file_name str =
  let fname1 =
    List.fold_right Filename.concat [Secure.base_dir (); "images"] str
  in
  if Sys.file_exists fname1 then fname1
  else search_in_lang_path (Filename.concat "images" str)
;

value png_image_size ic =
  let magic = let s = String.create 4 in do { really_input ic s 0 4; s } in
  if magic = "\137PNG" then do {
    seek_in ic 16;
    let wid = input_binary_int ic in
    let hei = input_binary_int ic in
    Some (wid, hei)
  }
  else None
;

value gif_image_size ic =
  let magic = let s = String.create 4 in do { really_input ic s 0 4; s } in
  if magic = "GIF8" then do {
    seek_in ic 6;
    let wid = let x = input_byte ic in input_byte ic * 256 + x in
    let hei = let x = input_byte ic in input_byte ic * 256 + x in
    Some (wid, hei)
  }
  else None
;

value jpeg_image_size ic =
  let magic =
    let str = String.create 10 in do { really_input ic str 0 10; str }
  in
  if Char.code magic.[0] = 0xff && Char.code magic.[1] = 0xd8 &&
     (let m = String.sub magic 6 4 in m = "JFIF" || m = "Exif") then
    let exif_type = String.sub magic 6 4 = "Exif" in
    let rec loop found =
      do {
        while Char.code (input_char ic) <> 0xFF do { () };
        let ch =
          loop (input_char ic) where rec loop ch =
            if Char.code ch = 0xFF then loop (input_char ic) else ch
        in
        if Char.code ch = 0xC0 || Char.code ch = 0xC3 then
          if exif_type && not found then
            loop True
          else do {
            for i = 1 to 3 do { let _ = input_char ic in () };
            let a = input_char ic in
            let b = input_char ic in
            let c = input_char ic in
            let d = input_char ic in
            let wid = Char.code c lsl 8 lor Char.code d in
            let hei = Char.code a lsl 8 lor Char.code b in
            Some (wid, hei)
          }
        else
          let a = input_char ic in
          let b = input_char ic in
          let len = Char.code a lsl 8 lor Char.code b in
          let len = if len >= 32768 then 0 else len in
          do {
            for i = 1 to len - 2 do { let _ = input_char ic in () };
            if Char.code ch <> 0xDA then loop found else None
          }
      }
    in
    loop False
  else None
;

value image_size fname =
  match try Some (Secure.open_in_bin fname) with [ Sys_error _ -> None ] with
  [ Some ic ->
      let r =
        try
          let sz = jpeg_image_size ic in
          let sz =
            if sz = None then do { seek_in ic 0; png_image_size ic } else sz
          in
          if sz = None then do { seek_in ic 0; gif_image_size ic } else sz
        with
        [ End_of_file -> None ]
      in
      do { close_in ic; r }
  | None -> None ]
;

value limited_image_size max_wid max_hei fname size =
  match
    if fname = "" then size
    else image_size fname
  with
  [ Some (wid, hei) ->
      let (wid, hei) =
        if hei > max_hei then
          let wid = wid * max_hei / hei in let hei = max_hei in (wid, hei)
        else (wid, hei)
      in
      let (wid, hei) =
        if wid > max_wid then
          let hei = hei * max_wid / wid in let wid = max_wid in (wid, hei)
        else (wid, hei)
      in
      Some (wid, hei)
  | None -> None ]
;

value find_person_in_env conf base suff =
  match p_getint conf.env ("i" ^ suff) with
  [ Some i ->
      if i >= 0 && i < nb_of_persons base then
        let p = pget conf base (Adef.iper_of_int i) in
        if is_hidden p then None
        else Some p
      else None
  | None ->
      match
        (p_getenv conf.env ("p" ^ suff), p_getenv conf.env ("n" ^ suff))
      with
      [ (Some p, Some n) ->
          let occ =
            match p_getint conf.env ("oc" ^ suff) with
            [ Some oc -> oc
            | None -> 0 ]
          in
          match person_of_key base p n occ with
          [ Some ip ->
              let p = pget conf base ip in
              if is_hidden p then None
              else if not conf.hide_names || authorized_age conf base p then
                Some p
              else None
          | None -> None ]
      | _ -> None ] ]
;

value person_exists conf base (fn, sn, oc) =
  match p_getenv conf.base_env "red_if_not_exist" with
  [ Some "off" -> True
  | Some _ | None ->
      match person_of_key base fn sn oc with
      [ Some ip -> authorized_age conf base (pget conf base ip)
      | None -> False ] ]
;

value find_sosa_ref conf base =
  match find_person_in_env conf base "z" with
  [ Some p -> Some p
  | None ->
      match p_getenv conf.base_env "default_sosa_ref" with
      [ Some n ->
          if n = "" then None
          else
            match person_ht_find_all base n with
            [ [ip] ->
                let p = pget conf base ip in
                if is_hidden p then None
                else Some p
            | _ -> None ]
      | None -> None ] ]
;

value create_topological_sort conf base =
  match p_getenv conf.env "opt" with
  [ Some "no_tsfile" ->
      let () = load_ascends_array base in
      let () = load_couples_array base in
      Consang.topological_sort base (pget conf)
  | Some "no_tstab" -> Array.create (nb_of_persons base) 0
  | _ ->
      let bfile = base_path [] (conf.bname ^ ".gwb") in
      lock (Mutil.lock_file bfile) with
      [ Accept ->
          let tstab_file =
            if conf.use_restrict then Filename.concat bfile "tstab_visitor"
            else Filename.concat bfile "tstab"
          in
          let r =
            match
              try
                Some (Secure.open_in_bin tstab_file) with
                [ Sys_error _ -> None ]
            with
            [ Some ic ->
                let r =
                  try Some (Marshal.from_channel ic) with
                  [ End_of_file | Failure _ -> None ]
                in
                do { close_in ic; r }
            | None -> None ]
          in
          match r with
          [ Some tstab -> tstab
          | None ->
              let () = load_ascends_array base in
              let () = load_couples_array base in
              let tstab = Consang.topological_sort base (pget conf) in
              do {
                if conf.use_restrict then base_visible_write base else ();
                match
                  try Some (Secure.open_out_bin tstab_file) with
                  [ Sys_error _ -> None ]
                with
                [ Some oc ->
                    do {
                      Marshal.to_channel oc tstab [Marshal.No_sharing];
                      close_out oc;
                    }
                | None -> () ];
                tstab
              } ]
      | Refuse ->
          let () = load_ascends_array base in
          let () = load_couples_array base in
          Consang.topological_sort base (pget conf) ] ]
;

value branch_of_sosa conf base ip n =
  do {
    if Num.eq n Num.zero then invalid_arg "branch_of_sosa" else ();
    let rec expand bl n =
      if Num.eq n Num.one then bl else expand [Num.even n :: bl] (Num.half n)
    in
    let rec loop ipl ip sp =
      fun
      [ [] -> Some [(ip, sp) :: ipl]
      | [goto_fath :: nl] ->
          match get_parents (pget conf base ip) with
          [ Some ifam ->
              let cpl = foi base ifam in
              if goto_fath then
                loop [(ip, sp) :: ipl] (get_father cpl) Male nl
              else loop [(ip, sp) :: ipl] (get_mother cpl) Female nl
          | _ -> None ] ]
    in
    loop [] ip (get_sex (pget conf base ip)) (expand [] n)
  }
;

value sosa_of_branch ipl =
  do {
    if ipl = [] then failwith "sosa_of_branch" else ();
    let ipl = List.tl (List.rev ipl) in
    List.fold_left
      (fun b (ip, sp) ->
         let b = Num.twice b in
         match sp with
         [ Male -> b
         | Female -> Num.inc b 1
         | Neuter -> assert False ])
      Num.one ipl
  }
;

value space_to_unders = Mutil.tr ' ' '_';

value default_image_name_of_key fnam surn occ =
  let f = space_to_unders (Name.lower fnam) in
  let s = space_to_unders (Name.lower surn) in
  f ^ "." ^ string_of_int occ ^ "." ^ s
;

value default_image_name base p =
  default_image_name_of_key (p_first_name base p) (p_surname base p)
    (get_occ p)
;

value auto_image_file conf base p =
  let s = default_image_name base p in
  let f = Filename.concat (base_path ["images"] conf.bname) s in
  if Sys.file_exists (f ^ ".gif") then Some (f ^ ".gif")
  else if Sys.file_exists (f ^ ".jpg") then Some (f ^ ".jpg")
  else if Sys.file_exists (f ^ ".png") then Some (f ^ ".png")
  else None
;

value image_and_size conf base p image_size =
  if not conf.no_image && authorized_age conf base p then
    match sou base (get_image p) with
    [ "" ->
        match auto_image_file conf base p with
        [ Some f -> Some (True, f, image_size f None)
        | None -> None ]
    | s ->
        let (s, size) =
          let l = String.length s - 1 in
          if s.[l] = ')' then
            try
              let pos1 = String.index s '(' in
              let pos2 = String.index_from s pos1 'x' in
              let wid = String.sub s (pos1+1) (pos2-pos1-1) in
              let hei = String.sub s (pos2+1) (l-pos2-1) in
              let size = Some (int_of_string wid, int_of_string hei) in
              (String.sub s 0 pos1, image_size "" size)
            with
            [ Not_found | Failure _ -> (s, None) ]
          else (s, None)
        in
        let http = "http://" in
        if String.length s > String.length http &&
           String.sub s 0 (String.length http) = http then
          Some (False, s, size)
        else if Filename.is_implicit s then
          match
            try Some (List.assoc "images_path" conf.base_env) with
            [ Not_found -> None ]
          with
          [ Some p when p <> "" -> Some (False, p ^ s, size)
          | _ ->
              let fname = personal_image_file_name conf.bname s in
              if Sys.file_exists fname then
                Some (True, fname, image_size fname None)
              else None ]
        else None ]
  else None
;

value has_image conf base p =
  if not conf.no_image && authorized_age conf base p then
    not (is_empty_string (get_image p)) || auto_image_file conf base p <> None
  else False
;

value gen_only_printable or_nl s =
  let s' = String.create (String.length s) in
  do {
    for i = 0 to String.length s - 1 do {
      s'.[i] :=
        if Mutil.utf_8_db.val && Char.code s.[i] > 127 then s.[i]
        else
          match s.[i] with
          [ ' '..'~' | '\160'..'\255' -> s.[i]
          | '\n' -> if or_nl then '\n' else ' '
          | _ -> ' ' ]
    };
    strip_spaces s'
  }
;

value only_printable_or_nl = gen_only_printable True;
value only_printable = gen_only_printable False;

value relation_type_text conf t n =
  match t with
  [ Adoption ->
      transl_nth conf "adoptive father/adoptive mother/adoptive parents" n
  | Recognition ->
      transl_nth conf
        "recognizing father/recognizing mother/recognizing parents" n
  | CandidateParent ->
      transl_nth conf "candidate father/candidate mother/candidate parents" n
  | GodParent -> transl_nth conf "godfather/godmother/godparents" n
  | FosterParent ->
      transl_nth conf "foster father/foster mother/foster parents" n ]
;

value rchild_type_text conf t n =
  match t with
  [ Adoption ->
      transl_nth conf "adoptive son/adoptive daughter/adoptive child" n
  | Recognition ->
      transl_nth conf "recognized son/recognized daughter/recognized child" n
  | CandidateParent ->
      transl_nth conf "candidate son/candidate daughter/candidate child" n
  | GodParent -> transl_nth conf "godson/goddaughter/godchild" n
  | FosterParent ->
      transl_nth conf "foster son/foster daughter/foster child" n ]
;

value wprint_hidden conf pref name valu =
  Wserver.wprint "<input type=\"hidden\" name=\"%s%s\" value=\"%s\"%s>\n"
    pref name (quote_escaped valu) conf.xhs
;

value wprint_hidden_person conf base pref p =
  let first_name = p_first_name base p in
  let surname = p_surname base p in
  if accessible_by_key conf base p first_name surname then do {
    wprint_hidden conf pref "p" (Name.lower first_name);
    wprint_hidden conf pref "n" (Name.lower surname);
    if get_occ p > 0 then
      wprint_hidden conf pref "oc" (string_of_int (get_occ p))
    else ();
  }
  else
    wprint_hidden conf pref "i"
      (string_of_int (Adef.int_of_iper (get_key_index p)))
;

exception Ok;

value has_nephews_or_nieces conf base p =
  try
    let a = p in
    match get_parents a with
    [ Some ifam ->
        let fam = foi base ifam in
        do {
          Array.iter
            (fun ip ->
               if ip = get_key_index p then ()
               else
                 Array.iter
                   (fun ifam ->
                      if Array.length (get_children (foi base ifam)) > 0 then
                        raise Ok
                      else ())
                   (get_family (pget conf base ip)))
            (get_children fam);
          False
        }
    | _ -> False ]
  with
  [ Ok -> True ]
;

value h s = Digest.to_hex (Digest.string s);
value max_login_time = 60.0; (* short, just for testing *)

value is_that_user_and_password auth_scheme user passwd =
  match auth_scheme with
  [ NoAuth -> False
  | TokenAuth ts -> user = ts.ts_user && passwd = ts.ts_pass
  | HttpAuth (Basic bs) -> user = bs.bs_user && passwd = bs.bs_pass
  | HttpAuth (Digest ds) ->
      if user <> ds.ds_username then False
      else
        let that_response_would_be =
          let a1 = sprintf "%s:%s:%s" user ds.ds_realm passwd in
          let a2 = sprintf "%s:%s" ds.ds_meth ds.ds_uri in
          if ds.ds_qop = "auth" || ds.ds_qop = "auth-int" then
            h (h a1 ^ ":" ^ ds.ds_nonce ^ ":" ^ ds.ds_nc ^ ":" ^
               ds.ds_cnonce ^ ":" ^ ds.ds_qop ^ ":" ^ h a2)
          else
            h (h a1 ^ ":" ^ ds.ds_nonce ^ ":" ^ h a2)
        in
        that_response_would_be = ds.ds_response ]
;

value browser_doesnt_have_tables conf =
  let user_agent = Wserver.extract_param "user-agent: " '/' conf.request in
  String.lowercase user_agent = "lynx"
;

(* Printing for browsers without tables *)

value pre_text_size txt =
  let rec normal len i =
    if i = String.length txt then len
    else if txt.[i] = '<' then in_tag len (i + 1)
    else if txt.[i] = '&' then in_char (len + 1) (i + 1)
    else normal (len + 1) (i + 1)
  and in_tag len i =
    if i = String.length txt then len
    else if txt.[i] = '>' then normal len (i + 1)
    else in_tag len (i + 1)
  and in_char len i =
    if i = String.length txt then len
    else if txt.[i] = ';' then normal len (i + 1)
    else in_char len (i + 1)
  in
  normal 0 0
;

value print_pre_center sz txt =
  do {
    for i = 1 to (sz - pre_text_size txt) / 2 do { Wserver.wprint " " };
    Wserver.wprint "%s\n" txt;
  }
;

value print_pre_left sz txt =
  let tsz = pre_text_size txt in
  do {
    if tsz < sz / 2 - 1 then
      for i = 2 to (sz / 2 - 1 - tsz) / 2 do { Wserver.wprint " " }
    else ();
    Wserver.wprint " %s\n" txt;
  }
;

value print_pre_right sz txt =
  let tsz = pre_text_size txt in
  do {
    if tsz < sz / 2 - 1 then do {
      for i = 1 to sz / 2 do { Wserver.wprint " " };
      for i = 1 to (sz / 2 - 1 - tsz) / 2 do { Wserver.wprint " " };
      ()
    }
    else for i = 1 to sz - pre_text_size txt - 1 do { Wserver.wprint " " };
    Wserver.wprint " %s\n" txt;
  }
;

value of_course_died conf p =
  match Adef.od_of_codate (get_birth p) with
  [ Some (Dgreg d _) -> conf.today.year - d.year > 120
  | _ -> False ]
;

value relation_txt conf sex fam =
  let is = index_of_sex sex in
  match get_relation fam with
  [ NotMarried | NoSexesCheckNotMarried ->
      ftransl_nth conf "relationship%t to" is
  | Married | NoSexesCheckMarried -> ftransl_nth conf "married%t to" is
  | Engaged -> ftransl_nth conf "engaged%t to" is
  | NoMention ->
      let s = "%t " ^ transl conf "with" in
      valid_format "%t" s ]
;

value escache_value base =
  let t = Gwdb.date_of_last_change base in
  let v = int_of_float (mod_float t (float_of_int max_int)) in
  string_of_int v
;

value adm_file f =
  List.fold_right Filename.concat [cnt_dir.val; "cnt"] f
;

value std_date conf =
  let (hour, min, sec) = conf.time in
  sprintf "%04d-%02d-%02d %02d:%02d:%02d" conf.today.year
    conf.today.month conf.today.day hour min sec
;

value read_wf_trace fname =
  match try Some (Secure.open_in fname) with [ Sys_error _ -> None ] with
  [ Some ic ->
      let r = ref [] in
      do {
        try while True do { r.val := [input_line ic :: r.val] } with
        [ End_of_file -> close_in ic ];
        List.rev r.val
      }
  | None -> [] ]
;

value write_wf_trace fname wt =
  let oc = Secure.open_out fname in
  do {
    List.iter (fun (dt, u) -> fprintf oc "%s %s\n" dt u) wt;
    close_out oc;
  }
;

value update_wf_trace conf fname =
  let dt = std_date conf in
  let wt =
    let r = read_wf_trace fname in
    let dtlen = String.length dt in
    let rec loop found r =
      fun
      [ [x :: l] ->
          if String.length x > dtlen + 2 then
            let u =
              String.sub x (dtlen + 1) (String.length x - dtlen - 1)
            in
            if u = conf.user then loop True [(dt, u) :: r] l
            else loop found [(String.sub x 0 dtlen, u) :: r] l
          else loop found r l
      | [] -> if found then r else [(dt, conf.user) :: r] ]
    in
    loop False [] r
  in
  write_wf_trace fname (List.sort (fun x y -> compare y x) wt)
;

value commit_patches conf base =
  do {
    Gwdb.commit_patches base;
    conf.henv :=
      List.map
        (fun (k, v) ->
           if k = "escache" then (k, escache_value base) else (k, v))
        conf.henv
    ;
    if conf.user <> "" then
      let wpf =
        try List.assoc "wizard_passwd_file" conf.base_env with
        [ Not_found -> "" ]
      in
      if wpf <> "" then
        let fname = adm_file (conf.bname ^ "_u.txt") in
        update_wf_trace conf fname
      else ()
    else ();
  }
;

value short_f_month m =
  match m with
  [ 1 -> "VD"
  | 2 -> "BR"
  | 3 -> "FM"
  | 4 -> "NI"
  | 5 -> "PL"
  | 6 -> "VT"
  | 7 -> "GE"
  | 8 -> "FL"
  | 9 -> "PR"
  | 10 -> "ME"
  | 11 -> "TH"
  | 12 -> "FT"
  | 13 -> "JC"
  | _ -> "" ]
;

(* reading password file *)

type auth_user = {au_user : string; au_passwd : string; au_info : string};

value read_gen_auth_file fname =
  let fname = base_path [] fname in
  match try Some (Secure.open_in fname) with [ Sys_error _ -> None ] with
  [ Some ic ->
      let rec loop data =
        match try Some (input_line ic) with [ End_of_file -> None ] with
        [ Some line ->
            let len = String.length line in
            let data =
              match
                try Some (String.index line ':') with [ Not_found -> None ]
              with
              [ Some i ->
                  let user = String.sub line 0 i in
                  let j =
                    try String.index_from line (i + 1) ':' with
                    [ Not_found -> len ]
                  in
                  let passwd = String.sub line (i + 1) (j - i - 1) in
                  let rest =
                    if j = len then ""
                    else String.sub line (j + 1) (len - j - 1)
                  in
                  let au =
                    {au_user = user; au_passwd = passwd; au_info = rest}
                  in
                  [au :: data]
              | None -> data ]
            in
            loop data
        | None -> do { close_in ic; List.rev data } ]
      in
      loop []
  | None -> [] ]
;

value start_equiv_with case_sens s m i =
  let rec test i j =
    if j = String.length s then Some i
    else if i = String.length m then None
    else if case_sens then
      if m.[i] = s.[j] then test (i + 1) (j + 1) else None
    else
      match Name.next_chars_if_equiv m i s j with
      [ Some (i, j) -> test i j
      | None -> None ]
  in
  if case_sens then
    if m.[i] = s.[0] then test (i + 1) 1 else None
  else
    match Name.next_chars_if_equiv m i s 0 with
    [ Some (i, j) -> test i j
    | None -> None ]
;

value rec in_text case_sens s m =
  loop False 0 where rec loop in_tag i =
    if i = String.length m then False
    else if in_tag then loop (m.[i] <> '>') (i + 1)
    else if m.[i] = '<' then loop True (i + 1)
    else if m.[i] = '[' && i + 1 < String.length m && m.[i+1] = '[' then
      match NotesLinks.misc_notes_link m i with
      [ NotesLinks.WLpage j _ _ _ text
      | NotesLinks.WLperson j _ text _
      | NotesLinks.WLwizard j _ text ->
          if in_text case_sens s text then True else loop False j
      | NotesLinks.WLnone -> loop False (i + 1) ]
    else
      match start_equiv_with case_sens s m i with
      [ Some _ -> True
      | None -> loop False (i + 1) ]
;

value html_highlight case_sens h s =
  let ht i j = "<span class=\"found\">" ^ String.sub s i (j - i) ^ "</span>" in
  loop False 0 0 where rec loop in_tag i len =
    if i = String.length s then Buff.get len
    else if in_tag then loop (s.[i] <> '>') (i + 1) (Buff.store len s.[i])
    else if s.[i] = '<' then loop True (i + 1) (Buff.store len s.[i])
    else
      match start_equiv_with case_sens h s i with
      [ Some j -> loop False j (Buff.mstore len (ht i j))
      | None -> loop False (i + 1) (Buff.store len s.[i]) ]
;

(* Wrapper to pretty print the produced XHTML (see Wserver.wrap_string) *)

value b = Buffer.create 80;
value ind_bol = ref 0;
value ind_curr = ref 0;
value bol = ref False;
value after_less = ref False;
value after_slash = ref False;
value curr_tag = ref None;
value stack_in_error = ref False;
value tag_stack = ref [];
value check_tag_stack c =
  if stack_in_error.val then ()
  else
    match curr_tag.val with
    [ Some (tag1, topen, tag_found) ->
        match c with
        [ ' ' -> curr_tag.val := Some (tag1, topen, True)
        | '>' ->
            if topen then do {
              tag_stack.val := [tag1 :: tag_stack.val];
              curr_tag.val := None
            }
            else
              match tag_stack.val with
              [ [tag2 :: rest] ->
                  if tag1 = tag2 then do {
                    tag_stack.val := rest;
                    curr_tag.val := None
                  }
                  else do {
                    Printf.eprintf "Tag <%s> ended by </%s>\n" tag2 tag1;
                    stack_in_error.val := True;
                  }
              | [] -> do {
                  Printf.eprintf "Ending tag not opened </%s>\n" tag1;
                  stack_in_error.val := True;
                } ]
        | c ->
            if tag_found then ()
            else curr_tag.val := Some (tag1 ^ String.make 1 c, topen, False) ]
    | None -> () ]
;
value xml_pretty_print s =
  loop 0 where rec loop i =
    if i = String.length s then ""
    else do {
      if bol.val then
        if s.[i] = ' ' || s.[i] = '\n' then loop (i + 1)
        else do {
          bol.val := False;
          loop i;
        }
      else
        match s.[i] with
        [ '\n' -> do {
            check_tag_stack ' ';
            let ind = min ind_bol.val ind_curr.val in
            let line = Buffer.contents b in
            bol.val := True;
            ind_bol.val := ind_curr.val;
            Buffer.clear b;
            String.make (max 0 ind) ' ' ^ line ^ "\n" ^ loop (i + 1)
          }
        | c -> do {
            let after_less_v = after_less.val in
            let after_slash_v = after_slash.val in
            after_less.val := False;
            after_slash.val := False;
            match c with
            [ '<' -> do {
                after_less.val := True;
                curr_tag.val := Some ("", True, False);
              }
            | '/' ->
                if after_less_v then do {
                  ind_curr.val := ind_curr.val - 2;
                  curr_tag.val := Some ("", False, False);
                }
                else after_slash.val := True
            | '!' -> curr_tag.val := None
            | '>' ->
                if after_slash_v then do {
                  ind_curr.val := ind_curr.val - 2;
                  curr_tag.val := None
                }
                else check_tag_stack c
            | c -> do {
                check_tag_stack c;
                if after_less_v then ind_curr.val := ind_curr.val + 2 else ();
              } ];
            Buffer.add_char b c;
            loop (i + 1)
          } ]
    }
;

(* Print list in columns with alphabetic order *)

type elem_kind = [ HeadElem | ContElem | Elem ];
value kind_size = fun [ HeadElem | ContElem -> 4 | Elem -> 1 ];

value dispatch_in_columns ncol list order =
  let rlist =
    List.fold_left
      (fun rlist elem ->
         let ord = order elem in
         let kind =
           match rlist with
           [ [(_, prev_ord, prev_elem) :: _] ->
               if ord = prev_ord ||
                  ord <> "" && prev_ord <> "" && ord.[0] = prev_ord.[0]
               then Elem
               else HeadElem
           | [] -> HeadElem ]
         in
         [(ref kind, ord, elem) :: rlist])
      [] list
  in
  let (ini_list, ini_len) =
    List.fold_left
      (fun (list, len) ((kind, _, _) as elem) ->
         ([elem :: list], len + kind_size kind.val))
      ([], 0) rlist
  in
  let len_list =
    loop [] 0 1 0 ini_len ini_list
    where rec loop rlen_list cnt col accu len list =
      if col > ncol then List.rev rlen_list
      else
        let (list, kind, is_last) =
          match list with
          [ [(kind, _, _) :: list] -> (list, kind, False)
          | [] -> ([], ref Elem, True) ]
        in
        let accu = accu + ncol * kind_size kind.val in
        let cnt = cnt + 1 in
        if accu > len && not is_last && kind.val = Elem then do {
          (* put a new size and restart from zero *)
          kind.val := ContElem;
          loop [] 0 1 0 (len + kind_size ContElem - 1) ini_list
        }
        else
          let (rlen_list, cnt, col, accu) =
            if accu > len && cnt > 1 then
              ([cnt - 1 :: rlen_list], 1, col + 1, accu - len)
            else
              (rlen_list, cnt, col, accu)
          in
          loop rlen_list cnt col accu len list
  in
  (len_list, ini_list)
;

value print_in_columns conf len_list list wprint_elem = do {
  begin_centered conf;
  tag "table" "width=\"95%%\" border=\"%d\"" conf.border begin
    tag "tr" "align=\"%s\" valign=\"top\"" conf.left begin
      let _ =
        List.fold_left
          (fun (list, first) len ->
             loop len list where rec loop n list =
               if n = 0 then do {
                 Wserver.wprint "</ul>\n</td>\n";
                 (list, False)
               }
               else
                 match list with
                 [ [(kind, ord, elem) :: list] -> do {
                     if n = len then Wserver.wprint "<td>\n"
                     else if kind.val <> Elem then Wserver.wprint "</ul>\n"
                     else ();
                     if kind.val <> Elem then do {
                       Wserver.wprint "<h3 style=\"border-bottom: \
                         dotted 1px\">%s%s</h3>\n"
                         (if ord = "" then "..." else String.make 1 ord.[0])
                         (if kind.val = HeadElem then ""
                          else " (" ^ transl conf "continued" ^ ")");
                       Wserver.wprint "<ul>\n";
                     }
                     else ();
                     stagn "li" begin wprint_elem elem; end;
                     loop (n - 1) list
                   }
                 | [] -> ([], False) ])
          (list, True) len_list
      in
      ();
    end;
  end;
  end_centered conf;
};

value wprint_in_columns conf order wprint_elem list =
  let (len_list, list) =
    let ncols =
      match p_getint conf.env "ncols" with
      [ Some n -> max 1 n
      | None -> if List.length list < 10 then 1 else 3 ]
    in
    dispatch_in_columns ncols list order
  in
  print_in_columns conf len_list list wprint_elem
;
