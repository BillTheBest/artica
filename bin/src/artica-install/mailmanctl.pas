unit mailmanctl;

{$MODE DELPHI}
{$LONGSTRINGS ON}

interface

uses
    Classes, SysUtils,variants,strutils,Process,logs,unix,
    RegExpr      in '/home/dtouzeau/developpement/artica-postfix/bin/src/artica-install/RegExpr.pas',
    zsystem      in '/home/dtouzeau/developpement/artica-postfix/bin/src/artica-install/zsystem.pas',
    openldap;


  type
  tmailman=class


private
     LOGS:Tlogs;
     SYS:TSystem;
     artica_path:string;
     MailManEnabled:integer;
     ldap:topenldap;


     procedure SET_CONFIG(KEY:string;value:string);
     function mmsitepass_path():string;

public
    procedure   Free;
    constructor Create(const zSYS:Tsystem);
    procedure   START();
    function    PID_NUM():string;
    procedure   STOP();
    function    STATUS():string;
    function    CONFIG_PATH():string;
    function    BIN_PATH():string;
    function    VERSION():string;
    function    IS_LIST_EXISTS(listname:string):boolean;
    procedure    AddNewList(listname:string;urlhost:string;smtpdomain:string;admin_mail:string;password:string);
    function    LIST():string;
    function    ListInfo(listname:string):string;
    procedure    DeleteNewList(listname:string);
    procedure   SAVE_GLOBAL_CONF();
    procedure   PUBLIC_ARCHIVES_ON_PHP();
    function    PostFixToMailManPath():string;
    function    IS_MAILMAN_IN_MASTER():boolean;
    function    ADD_MAILMAN_IN_MASTER():boolean;
    function    GET_CONFIG(KEY:string):string;
    function    PID_PATH():string;
END;

implementation

constructor tmailman.Create(const zSYS:Tsystem);
begin
       forcedirectories('/etc/artica-postfix');
       LOGS:=tlogs.Create();
       SYS:=zSYS;
       ldap:=topenldap.Create;
        if not TryStrToInt(SYS.GET_INFO('MailManEnabled'),MailManEnabled)  then begin
           SYS.set_INFO('MailManEnabled','0');
           MailManEnabled:=0;
        end;

       if not DirectoryExists('/usr/share/artica-postfix') then begin
              artica_path:=ParamStr(0);
              artica_path:=ExtractFilePath(artica_path);
              artica_path:=AnsiReplaceText(artica_path,'/bin/','');

      end else begin
          artica_path:='/usr/share/artica-postfix';
      end;
end;
//##############################################################################
procedure tmailman.free();
begin
    logs.Free;
end;
//##############################################################################
function tmailman.PID_NUM():string;
var pid:string;
begin
pid :=SYS.GET_PID_FROM_PATH(PID_PATH());
if length(pid)=0 then pid:=SYS.PIDOF(BIN_PATH());
result:=pid;
end;
//##############################################################################
function tmailman.PID_PATH():string;
begin
if FileExists('/var/run/mailman/mailman.pid') then exit('/var/run/mailman/mailman.pid');
if FileExists('/var/lib/mailman/data/master-qrunner.pid') then exit('/var/lib/mailman/data/master-qrunner.pid');
if FileExists('/var/run/mailman/master-qrunner.pid') then exit('/var/run/mailman/master-qrunner.pid');
end;
//##############################################################################
function tmailman.BIN_PATH():string;
begin
if FileExists('/usr/lib/mailman/bin/mailmanctl') then exit('/usr/lib/mailman/bin/mailmanctl');
end;
//##############################################################################
function tmailman.CONFIG_PATH():string;
begin
///var/lib/mailman/bin/list_lists
if FileExists('/usr/lib/mailman/Mailman/mm_cfg.py') then exit('/usr/lib/mailman/Mailman/mm_cfg.py');
if FileExists('/etc/mailman/mm_cfg.py') then exit('/etc/mailman/mm_cfg.py');
end;
//##############################################################################
function tmailman.mmsitepass_path():string;
begin
if FileExists('/usr/lib/mailman/bin/mmsitepass') then exit('/usr/lib/mailman/bin/mmsitepass');
end;
//##############################################################################
function tmailman.PostFixToMailManPath():string;
begin
if FileExists('/etc/mailman/postfix-to-mailman.py') then exit('/etc/mailman/postfix-to-mailman.py');
if FileExists('/usr/lib/mailman/bin/postfix-to-mailman.py') then exit('/usr/lib/mailman/bin/postfix-to-mailman.py');
if FileExists('/usr/share/mailman/postfix-to-mailman.py') then exit('/usr/share/mailman/postfix-to-mailman.py');
end;
//##############################################################################
procedure tmailman.START();
var

   pid:string;
   count:integer;
   RegExpr        :TRegExpr;
   servername:string;
   DEFAULT_EMAIL_HOST:string;
begin

  DEFAULT_EMAIL_HOST:=trim(SYS.GET_INFO('MAILMAN_DEFAULT_EMAIL_HOST'));



  count:=0;
  logs.DebugLogs('############## Mailman #######################');

  if not FileExists(BIN_PATH()) then begin
     logs.Syslogs('Starting......: mailman is not installed');
     exit;
  end;

  if MailManEnabled=0 then begin
      logs.Syslogs('Starting......: mailman is disabled by MailManEnabled value');
      STOP();
      exit;
  end;


  pid:=PID_NUM();
  logs.DebugLogs('tmailman.START(): PID report "' + PID_NUM()+'"');


   if SYS.PROCESS_EXIST(pid) then begin
      logs.DebugLogs('Starting......: mailman daemon is already running using PID ' + pid + '...');
      exit;
   end;


  logs.DebugLogs('Starting......: mailman daemon cleaning...');
  if FileExists(mmsitepass_path()) then logs.OutputCmd(mmsitepass_path()+' '+ldap.get_LDAP('password'));
  RegExpr:=TRegExpr.Create;

  if length(DEFAULT_EMAIL_HOST)=0 then begin
      servername:=GET_CONFIG('DEFAULT_EMAIL_HOST');
      RegExpr.Expression:='^(.+?)\.(.+)';
      if not RegExpr.Exec(servername) then begin
         logs.DebugLogs('Starting......: mailman changing servername to "'+servername+'.localhost.localdomain"');
         SET_CONFIG('DEFAULT_EMAIL_HOST',servername+'.localhost.localdomain');
         SYS.set_INFO('MAILMAN_DEFAULT_EMAIL_HOST',servername+'.localhost.localdomain');
      end;
  end else begin
     SET_CONFIG('DEFAULT_EMAIL_HOST',DEFAULT_EMAIL_HOST);
  end;




  if not IS_LIST_EXISTS('mailman') then begin
       logs.DebugLogs('Starting......: mailman create first list "mailman"');
       AddNewList('mailman','localhost.localdomain','localhost.localdomain','root@localhost.localdomain',ldap.get_LDAP('password'));
  end;
  logs.OutputCmd(SYS.LOCATE_PHP5_BIN()+' /usr/share/artica-postfix/exec.mailman.php');
  
  logs.OutputCmd('/etc/init.d/mailman start');


  pid:=PID_NUM();
  while not SYS.PROCESS_EXIST(pid) do begin

        sleep(500);
        count:=count+1;
        logs.DebugLogs('tmailman.START(): wait sequence ' + intToStr(count) + ' PID=' + pid);
        if count>20 then begin
            logs.DebugLogs('Starting......: mailman daemon failed...');
            exit;
        end;
        pid:=PID_NUM();
  end;
  logs.Syslogs('Success starting mailman daemon...');
  logs.DebugLogs('Starting......: mailman daemon success...');
end;
//##############################################################################
procedure tmailman.AddNewList(listname:string;urlhost:string;smtpdomain:string;admin_mail:string;password:string);
var cmd:string;
begin
  cmd:='/usr/lib/mailman/bin/newlist --urlhost='+urlhost+' --emailhost='+smtpdomain+' '+listname+' '+admin_mail+' '+password+' -q &';
  logs.Debuglogs(cmd);
  fpsystem(cmd);
end;
//##############################################################################
procedure tmailman.DeleteNewList(listname:string);
var cmd:string;
begin
  cmd:='/usr/lib/mailman/bin/rmlist '+listname;
  logs.OutputCmd(cmd);
end;
//##############################################################################
function tmailman.ListInfo(listname:string):string;
var cmd,tmpstr:string;
   RegExpr        :TRegExpr;
   l              :TstringList;
   r              :TstringList;
   i              :integer;
begin
  tmpstr:=logs.FILE_TEMP();

  cmd:='/usr/lib/mailman/bin/config_list -o '+tmpstr+' '+ listname;
  logs.OutputCmd(cmd);
  if not FileExists(tmpstr) then exit;
  l:=TstringList.Create;
  r:=TstringList.Create;
  RegExpr:=TRegExpr.Create;
  l.LoadFromFile(tmpstr);
  logs.DeleteFile(tmpstr);
  r.Add('[INFO]');
  for i:=0 to l.Count-1 do begin
      RegExpr.Expression:='^subject_prefix.+?''(.+?)''';
      if RegExpr.Exec(l.Strings[i]) then r.Add('subject_prefix='+RegExpr.Match[1]);

      RegExpr.Expression:='^host_name.+?''(.+?)''';
      if RegExpr.Exec(l.Strings[i]) then r.Add('host_name='+RegExpr.Match[1]);

      RegExpr.Expression:='^owner.+?''(.+?)''';
      if RegExpr.Exec(l.Strings[i]) then r.Add('owner='+RegExpr.Match[1]);
  

  end;
  
 result:=r.Text;
 r.free;
 l.free;
 RegExpr.free;
end;
//##############################################################################


function tmailman.LIST():string;
var
   tmpstr,cmd:string;
   RegExpr        :TRegExpr;
   F              :TstringList;
   i              :integer;
   ll             :string;
begin
   result:='';
   ll:='';
   tmpstr:=logs.FILE_TEMP();
   cmd:='/usr/lib/mailman/bin/list_lists -a >'+tmpstr+' 2>&1';
   logs.Debuglogs(cmd);
   fpsystem(cmd);
   F:=TstringList.Create;
   if FileExists(tmpstr) then F.LoadFromFile(tmpstr);
   logs.DeleteFile(tmpstr);
   RegExpr:=TRegExpr.Create;
   RegExpr.ModifierI:=true;
   RegExpr.Expression:='^\s+(.+?) -';
   for i:=0 to F.Count-1 do begin
       if RegExpr.Exec(F.Strings[i]) then begin
          ll:=ll+RegExpr.Match[1]+',';
       end;
   end;
result:=ll;
F.free;
RegExpr.free;
end;
//##############################################################################

function tmailman.IS_LIST_EXISTS(listname:string):boolean;
var
   tmpstr,cmd:string;
   RegExpr        :TRegExpr;
   F              :TstringList;
   i              :integer;
begin
   result:=false;
   tmpstr:=logs.FILE_TEMP();
   cmd:='/usr/lib/mailman/bin/list_lists -a >'+tmpstr+' 2>&1';
   logs.Debuglogs(cmd);
   fpsystem(cmd);
   F:=TstringList.Create;
   if FileExists(tmpstr) then F.LoadFromFile(tmpstr);
   logs.DeleteFile(tmpstr);
   RegExpr:=TRegExpr.Create;
   RegExpr.ModifierI:=true;
   RegExpr.Expression:=listname+'\s+';
   for i:=0 to F.Count-1 do begin
       if RegExpr.Exec(F.Strings[i]) then begin
          result:=true;
          break;
       end else begin
       end;
   end;

F.free;
RegExpr.free;

end;




procedure tmailman.STOP();
var
   pid:string;
   count:integer;
begin


  if not FileExists(BIN_PATH()) then begin
     writeln('Stopping mailman..........: not installed');
     exit;
  end;

pid:=PID_NUM();
count:=0;

if SYS.PROCESS_EXIST(pid) then begin
   writeln('Stopping mailman..........: ' + pid + ' PID..');
   fpsystem('/bin/kill ' + pid);
end else begin
    writeln('Stopping mailman..........: Already stopped');
    exit;
end;

  pid:=PID_NUM();
  while SYS.PROCESS_EXIST(pid) do begin
        pid:=PID_NUM();
        sleep(100);
        count:=count+1;
        if count>20 then begin
            writeln('Stopping mailman..........: timeout');
            fpsystem('/bin/kill -9 ' + pid);
        end;
  end;

pid:=PID_NUM();
if not SYS.PROCESS_EXIST(pid) then writeln('Stopping mailman..........: success');

//DEFAULT_EMAIL_HOST

end;

//##############################################################################
function tmailman.GET_CONFIG(KEY:string):string;
var
   RegExpr        :TRegExpr;
   F              :TstringList;
   i              :integer;
begin

  F:=TstringList.Create;


  if FileExists(CONFIG_PATH()) then F.LoadFromFile(CONFIG_PATH());
  RegExpr:=TRegExpr.Create;
  RegExpr.Expression:='^'+KEY+'[\s=]+''(.+?)''';

  For i:=0 to F.Count-1 do begin
     if RegExpr.Exec(F.Strings[i]) then begin
        result:=RegExpr.Match[1];
        break;
     end;
  end;

F.free;
RegExpr.Free;
end;
//##############################################################################
procedure tmailman.SET_CONFIG(KEY:string;value:string);
var
   RegExpr        :TRegExpr;
   F              :TstringList;
   i              :integer;
   D              :boolean;
   towrite        :string;
begin
  D:=false;
  F:=TstringList.Create;
  towrite:=KEY+' = '+''''+value+'''';

  if FileExists(CONFIG_PATH()) then F.LoadFromFile(CONFIG_PATH());
  RegExpr:=TRegExpr.Create;
  RegExpr.Expression:='^'+KEY;

  For i:=0 to F.Count-1 do begin
     if RegExpr.Exec(F.Strings[i]) then begin
        F.Strings[i]:=towrite;
        D:=True;
        break;
     end;
  end;

if not D then F.Add(towrite);
F.SaveToFile(CONFIG_PATH());
F.free;
RegExpr.Free;
end;
//##############################################################################
function tmailman.VERSION():string;
var
   RegExpr        :TRegExpr;
   F              :TstringList;
   i              :integer;
   tmpstr:string;
begin

  if not FileExists('/usr/lib/mailman/bin/version') then begin
     exit;
  end;
  tmpstr:=LOGS.FILE_TEMP();
  fpsystem('/usr/lib/mailman/bin/version >'+tmpstr +' 2>&1');
  F:=TstringList.Create;

  if FileExists(tmpstr) then F.LoadFromFile(tmpstr);
  RegExpr:=TRegExpr.Create;
  RegExpr.Expression:='([0-9\.\-]+)';

  For i:=0 to F.Count-1 do begin
     if RegExpr.Exec(F.Strings[i]) then begin
        result:=RegExpr.Match[1];
        break;
     end;
  end;
F.free;
RegExpr.Free;
end;
//##############################################################################
function tmailman.STATUS():string;
var pidpath:string;
begin
if not FileExists(BIN_PATH()) then exit;
SYS.MONIT_DELETE('APP_MAILMAN');
pidpath:=logs.FILE_TEMP();
fpsystem(SYS.LOCATE_PHP5_BIN()+' /usr/share/artica-postfix/exec.status.php --mailman >'+pidpath +' 2>&1');
result:=logs.ReadFromFile(pidpath);
logs.DeleteFile(pidpath);
end;
//#########################################################################################
procedure tmailman.SAVE_GLOBAL_CONF();
var
   MailManDefaultUriPattern:string;
   MailManDefaultArchiveUri:string;
begin
   SET_CONFIG('MTA','Postfix');
   MailManDefaultUriPattern:=SYS.GET_INFO('MailManDefaultUriPattern');
   MailManDefaultArchiveUri:=SYS.GET_INFO('MailManDefaultArchiveUri');
   if length(MailManDefaultUriPattern)>0 then begin
     SET_CONFIG('DEFAULT_URL_PATTERN',MailManDefaultUriPattern);
   end;
   
   if length(MailManDefaultArchiveUri)>0 then begin
     SET_CONFIG('PUBLIC_ARCHIVE_URL',MailManDefaultArchiveUri);
   end;
end;
//#########################################################################################
procedure tmailman.PUBLIC_ARCHIVES_ON_PHP();
var
   i:integer;
   newpath:string;
   l:TstringList;
begin

    l:=TstringList.Create;
    l.Add('<?php');
    l.Add('header("location:index.html");');
    l.Add('?>');
    
    if not DirectoryExists('/var/lib/mailman/archives/public') then exit;
    SYS.DirDir('/var/lib/mailman/archives/public');
    for i:=0 to SYS.DirListFiles.Count-1 do begin
        newpath:='/var/lib/mailman/archives/public/'+SYS.DirListFiles.Strings[i]+'/index.php';
        if not FileExists(newpath) then begin
            l.SaveToFile(newpath);
            logs.OutputCmd('/bin/chmod 755 ' + newpath);
            logs.OutputCmd('/bin/chown www-data:www-data ' + newpath);
        end;
    end;
end;
//#########################################################################################
function tmailman.IS_MAILMAN_IN_MASTER():boolean;
var
   i:integer;
   l:TstringList;
   RegExpr        :TRegExpr;
begin
result:=false;
if not FileExists('/etc/postfix/master.cf') then exit;
l:=TstringList.Create;
l.LoadFromFile('/etc/postfix/master.cf');
RegExpr:=TRegExpr.Create;
RegExpr.Expression:='^mailman\s+unix';
for i:=0 to l.Count-1 do begin
    if RegExpr.Exec(l.Strings[i]) then begin
       result:=true;
       break;
    end;
end;
RegExpr.free;
l.free;
end;
//#########################################################################################
function tmailman.ADD_MAILMAN_IN_MASTER():boolean;
var
   l:TstringList;
begin
result:=false;
if not FileExists('/etc/postfix/master.cf') then exit;
l:=TstringList.Create;
l.LoadFromFile('/etc/postfix/master.cf');
result:=false;
l.Add('mailman 		unix 	- 	n 	n 	- 	- 	pipe');
l.Add(' flags=FR user=mail:mail argv='+PostFixToMailManPath()+' ${nexthop} ${mailbox}');
try
   l.SaveToFile('/etc/postfix/master.cf');

except
   logs.Syslogs('ADD_MAILMAN_IN_MASTER(): warning, fatal error on writing /etc/postfix/master.cf file' );
   exit;
end;
result:=true;
l.free;
end;
//#########################################################################################
end.
