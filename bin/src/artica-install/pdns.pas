unit pdns;

{$MODE DELPHI}
{$LONGSTRINGS ON}

interface

uses
    Classes, SysUtils,variants,strutils,Process,logs,unix,RegExpr,zsystem,openldap,tcpip,bind9;



  type
  tpdns=class


private
     LOGS:Tlogs;
     SYS:TSystem;
     artica_path:string;
     zldap:Topenldap;
     cdirlist:string;
    procedure   WRITE_INITD();
    function   CONTROL_BIN_PATH():string;
    function   RECURSOR_BIN_PATH():string;
    function   RECURSOR_PID_NUM():string;

public
    procedure   Free;
    constructor Create(const zSYS:Tsystem);
    procedure   CONFIG_DEFAULT();

    function    VERSION():string;
    function    BIN_PATH():string;
    function    PID_NUM():string;
    procedure   START();
    procedure   STOP();
    procedure   RECURSOR_STOP();
    procedure   RECURSOR_START();
    function    STATUS:string;

END;

implementation

constructor tpdns.Create(const zSYS:Tsystem);
begin
       forcedirectories('/etc/artica-postfix');
       LOGS:=tlogs.Create();
       SYS:=zSYS;
       zldap:=Topenldap.Create;


       if not DirectoryExists('/usr/share/artica-postfix') then begin
              artica_path:=ParamStr(0);
              artica_path:=ExtractFilePath(artica_path);
              artica_path:=AnsiReplaceText(artica_path,'/bin/','');

      end else begin
          artica_path:='/usr/share/artica-postfix';
      end;
end;
//##############################################################################
procedure tpdns.free();
begin
    logs.Free;
    zldap.Free;
end;
//##############################################################################
function tpdns.BIN_PATH():string;
begin
   exit(SYS.LOCATE_PDNS_BIN());

end;
//##############################################################################
function tpdns.RECURSOR_BIN_PATH():string;
begin
   if FileExists('/usr/sbin/pdns_recursor') then exit('/usr/sbin/pdns_recursor');

end;
//##############################################################################
function tpdns.CONTROL_BIN_PATH():string;
begin
   if FileExists('/usr/sbin/pdns_control') then exit('/usr/sbin/pdns_control');

end;
//##############################################################################
function tpdns.PID_NUM():string;
begin
    if not FIleExists(BIN_PATH()) then exit;
    result:=SYS.PIDOF(BIN_PATH());
end;
//##############################################################################
function tpdns.RECURSOR_PID_NUM():string;
begin
    if not FIleExists(RECURSOR_BIN_PATH()) then exit;
    result:=SYS.PIDOF(RECURSOR_BIN_PATH());
end;
//##############################################################################

function tpdns.VERSION():string;
var
    RegExpr:TRegExpr;
    FileDatas:TStringList;
    i:integer;
    filetmp:string;
begin

result:=SYS.GET_CACHE_VERSION('APP_PDNS');
if length(result)>0 then exit;

filetmp:=logs.FILE_TEMP();
if not FileExists(BIN_PATH()) then begin
   logs.Debuglogs('unable to find pdns');
   exit;
end;

logs.Debuglogs(BIN_PATH()+' --version >'+filetmp+' 2>&1');
fpsystem(BIN_PATH()+' --version >'+filetmp+' 2>&1');

    RegExpr:=TRegExpr.Create;
    RegExpr.Expression:='Version:\s+([0-9\.]+)';
    FileDatas:=TStringList.Create;
    FileDatas.LoadFromFile(filetmp);
    logs.DeleteFile(filetmp);
    for i:=0 to FileDatas.Count-1 do begin
        writeln(FileDatas.Strings[i]);
        if RegExpr.Exec(FileDatas.Strings[i]) then begin
             result:=RegExpr.Match[1];
             break;
        end;
    end;
             RegExpr.free;
             FileDatas.Free;
if length(trim(result))=0 then result:='2.9.22';
SYS.SET_CACHE_VERSION('APP_PDNS',result);

end;
//#############################################################################
procedure tpdns.WRITE_INITD();
var
   l:TstringList;
   initPath:string;
begin
initPath:='';
l:=TstringList.Create;
if length(initPath)=0 then initPath:='/etc/init.d/pdns';

l.add('#! /bin/sh');
l.add('#');
l.add('# pdns		Startup script for the PowerDNS');
l.add('#');
l.add('#');
l.add('### BEGIN INIT INFO');
l.add('# Provides:          pdns');
l.add('# Required-Start:    $local_fs $network');
l.add('# Required-Stop:     $local_fs $network');
l.add('# Should-Start:      $named');
l.add('# Should-Stop:       $named');
l.add('# Default-Start:     2 3 4 5');
l.add('# Default-Stop:      0 1 6');
l.add('# Short-Description: PowerDNS');
l.add('### END INIT INFO');
l.add('');
l.add('PATH=/bin:/usr/bin:/sbin:/usr/sbin');
l.add('');
l.add('');
l.add('start () {');
l.add('	/etc/init.d/artica-postfix start pdns');
l.add('}');
l.add('');
l.add('stop () {');
l.add('      /etc/init.d/artica-postfix stop pdns');
l.add('}');
l.add('');
l.add('case "$1" in');
l.add('    start)');
l.add('	/etc/init.d/artica-postfix start pdns');
l.add('	;;');
l.add('    stop)');
l.add('	/etc/init.d/artica-postfix stop pdns');
l.add('	;;');
l.add('    reload|force-reload)');
l.add('	/etc/init.d/artica-postfix stop pdns');
l.add('	/etc/init.d/artica-postfix start pdns');
l.add('	;;');
l.add('    restart)');
l.add('	/etc/init.d/artica-postfix stop pdns');
l.add('	/etc/init.d/artica-postfix start pdns');
l.add('	;;');
l.add('    *)');
l.add('	echo "Usage: '+initPath+' {start|stop|reload|force-reload|restart}"');
l.add('	exit 3');
l.add('	;;');
l.add('esac');
l.add('');
l.add('exit 0');

l.SaveToFile(initPath);
fpsystem('/bin/chmod 755 '+initPath);
l.free;


end;

//#############################################################################
procedure tpdns.START();
var
   count:integer;
   pid:string;
   bind9:tbind9;
   loglevel:integer;
   straces:string;
begin
    pid:=PID_NUM();
     if not TryStrToInt(SYS.GET_INFO('PowerDNSLogLevel'),loglevel) then loglevel:=1;
    IF sys.PROCESS_EXIST(pid) then begin
       logs.DebugLogs('Starting......: PowerDNS Already running PID '+ pid);
       exit;
    end;
    bind9:=Tbind9.Create(SYS);
    if not FIleExists(BIN_PATH()) then begin
       logs.DebugLogs('Starting......: PowerDNS is not installed');
       exit;
    end;


    if FileExists('/etc/init.d/pdns') then begin
       if not FileExists('/etc/init.d/pdns.bak') then fpsystem('/bin/mv /etc/init.d/pdns /etc/init.d/pdns.bak');
       WRITE_INITD();
    end;

    forcedirectories('/var/run/pdns');
    CONFIG_DEFAULT();

    bind9.STOP();
    if loglevel>9 then straces:=' --log-dns-details --log-failed-updates ';
    fpsystem(BIN_PATH()+' --daemon --guardian=yes --recursor=127.0.0.1:1553 --config-dir=/etc/powerdns --lazy-recursion=yes'+straces);
    count:=0;

 while not SYS.PROCESS_EXIST(PID_NUM()) do begin

        sleep(100);
        inc(count);
        if count>10 then begin
           logs.DebugLogs('Starting......: PowerDNS (timeout)');
           break;
        end;
  end;

pid:=PID_NUM();
    IF sys.PROCESS_EXIST(pid) then begin
       logs.DebugLogs('Starting......: PowerDNS successfully started and running PID '+ pid);
       RECURSOR_START();
       exit;
    end;

logs.DebugLogs('Starting......: PowerDNS failed');

end;


//#############################################################################
procedure tpdns.RECURSOR_START();
var
   count:integer;
   pid,trace:string;
   loglevel:integer;
begin
    pid:=RECURSOR_PID_NUM();
    IF sys.PROCESS_EXIST(pid) then begin
       logs.DebugLogs('Starting......: PowerDNS Recursor Already running PID '+ pid);
       exit;
    end;

    if not FIleExists(RECURSOR_BIN_PATH()) then begin
       logs.DebugLogs('Starting......: PowerDNS Recursor is not installed');
       exit;
    end;

    if not TryStrToInt(SYS.GET_INFO('PowerDNSLogLevel'),loglevel) then loglevel:=1;
    forcedirectories('/var/run/pdns');
    if loglevel>9 then trace:=' --trace';
    fpsystem(RECURSOR_BIN_PATH()+' --daemon --export-etc-hosts --quiet=no --config-dir=/etc/powerdns'+trace);
    count:=0;
 while not SYS.PROCESS_EXIST(RECURSOR_PID_NUM()) do begin

        sleep(100);
        inc(count);
        if count>10 then begin
           logs.DebugLogs('Starting......: PowerDNS Recursor (timeout)');
           break;
        end;
  end;

pid:=RECURSOR_PID_NUM();
    IF sys.PROCESS_EXIST(pid) then begin
       logs.DebugLogs('Starting......: PowerDNS Recursor successfully started and running PID '+ pid);
       exit;
    end;

logs.DebugLogs('Starting......: PowerDNS Recursor failed');

end;


//#############################################################################
procedure tpdns.STOP();
var
   count:integer;
   pid:string;
begin
    if FileExists('/etc/init.d/pdns') then begin
       if not FileExists('/etc/init.d/pdns.bak') then fpsystem('/bin/mv /etc/init.d/pdns /etc/init.d/pdns.bak');
       WRITE_INITD();
    end;

    CONFIG_DEFAULT();

pid:=PID_NUM();
    IF not sys.PROCESS_EXIST(pid) then begin
       writeln('Stopping PowerDNS............: Already stopped');
       RECURSOR_STOP();
       exit;
    end;

    writeln('Stopping PowerDNS............: Stopping Smoothly PID '+pid);
    if FileExists(CONTROL_BIN_PATH()) then begin
       count:=0;
       logs.OutputCmd(CONTROL_BIN_PATH() +' stop');
       pid:=PID_NUM();
       while SYS.PROCESS_EXIST(pid) do begin
            sleep(100);
            inc(count);
        if count>10 then begin
           logs.DebugLogs('Starting......: PowerDNS (timeout)');
           break;
        end;
        pid:=PID_NUM()
      end;
    end;

pid:=PID_NUM();
IF not sys.PROCESS_EXIST(pid) then begin
       writeln('Stopping PowerDNS............: Successfully stopped');
       exit;
    end;

    writeln('Stopping PowerDNS............: Stopping PID '+pid);
       logs.OutputCmd('/bin/kill '+pid);
       count:=0;
       pid:=PID_NUM();
       while SYS.PROCESS_EXIST(pid) do begin
            sleep(100);
            inc(count);
        if count>10 then begin
           writeln('Stopping PowerDNS............: time-out');
           break;
        end;
         logs.OutputCmd('/bin/kill '+pid);
         pid:=PID_NUM();
     end;


pid:=PID_NUM();
IF not sys.PROCESS_EXIST(pid) then begin
       writeln('Stopping PowerDNS............: Successfully stopped');
       RECURSOR_STOP();
       exit;
    end;



       writeln('Stopping PowerDNS............: Failed');

end;


//#############################################################################
procedure tpdns.RECURSOR_STOP();
var
   count:integer;
   pid:string;
begin


pid:=RECURSOR_PID_NUM();
    IF not sys.PROCESS_EXIST(pid) then begin
       writeln('Stopping PowerDNS Recursor...: Already stopped');
       exit;
    end;

    writeln('Stopping PowerDNS Recursor...: Stopping Smoothly PID '+pid);                                                                                                                               

       logs.OutputCmd('/bin/kill '+pid);
       count:=0;
       pid:=RECURSOR_PID_NUM();
       while SYS.PROCESS_EXIST(pid) do begin
            sleep(100);
            inc(count);
        if count>10 then begin
           writeln('Stopping PowerDNS Recursor...: time-out');
           break;
        end;
         logs.OutputCmd('/bin/kill '+pid);
         pid:=RECURSOR_PID_NUM();
     end;


pid:=RECURSOR_PID_NUM();
IF not sys.PROCESS_EXIST(pid) then begin
       writeln('Stopping PowerDNS Recursor...: Successfully stopped');
       exit;
    end;



    writeln('Stopping PowerDNS Recursor...: Failed');

end;


//#############################################################################
function tpdns.STATUS:string;
var
pidpath:string;
begin
   SYS.MONIT_DELETE('APP_PDNS');
   SYS.MONIT_DELETE('APP_PDNS_RECURSOR');
pidpath:=logs.FILE_TEMP();
fpsystem(SYS.LOCATE_PHP5_BIN()+' /usr/share/artica-postfix/exec.status.php --pdns >'+pidpath +' 2>&1');
result:=logs.ReadFromFile(pidpath);
logs.DeleteFile(pidpath);

end;
//#############################################################################
procedure tpdns.CONFIG_DEFAULT();
var
   l:Tstringlist;
   z:Tstringlist;
   tcp:ttcpip;
   i:integer;
   ipstr:string;
   iplist:string;
   cdirtmp:string;
   loglevel:integer;
   ldapserver:string;
   localldap:boolean;
begin
iplist:='';
ForceDirectories('/etc/powerdns/pdns.d');
if not TryStrToInt(SYS.GET_INFO('PowerDNSLogLevel'),loglevel) then loglevel:=1;
tcp:=ttcpip.Create;
z:=Tstringlist.Create;
z.AddStrings(tcp.InterfacesStringList());
cdirlist:='127.0.0.0/8,127.0.0.1,';
for i:=0 to z.Count-1 do begin
    if(length(z.Strings[i]))=0 then continue;
    if z.Strings[i]='vmnet1' then continue;
    if z.Strings[i]='vmnet8' then continue;
    if z.Strings[i]='tun0' then continue;
   // writeln('interface:',z.Strings[i]);
    ipstr:=tcp.IP_ADDRESS_INTERFACE(z.Strings[i]);
    if ipstr='0.0.0.0' then continue;
    logs.DebugLogs('Starting......: PowerDNS listen IP address '+ipstr);
    cdirtmp:=tcp.CDIR(ipstr);

    if length(cdirtmp)>0 then begin
       if pos(cdirtmp,' '+cdirlist)=0 then cdirlist:=cdirlist+cdirtmp+',';
    end;

    if pos(ipstr,' '+iplist)=0 then iplist:=iplist+ipstr+',';
end;
 logs.DebugLogs('Starting......: PowerDNS log level '+IntToStr(loglevel));
l:=Tstringlist.Create;
ldapserver:=zldap.ldap_settings.servername;
 if Copy(iplist,length(iplist),1)=',' then iplist:=Copy(iplist,1,length(iplist)-1);
 if Copy(cdirlist,length(cdirlist),1)=',' then cdirlist:=Copy(cdirlist,1,length(cdirlist)-1);


//if ldapserver='127.0.0.1' then ldapserver:='localhost';
l.add('#allow-recursion='+cdirlist);
l.add('allow-recursion=0.0.0.0/0 ');
l.add('#allow-recursion-override=on');
l.add('cache-ttl=20');
l.add('# chroot=/var/spool/powerdns');
l.add('config-dir=/etc/powerdns');
l.add('# config-name=');
l.add('# control-console=no');
l.add('daemon=yes');
l.add('# default-soa-name=a.misconfigured.powerdns.server');
l.add('disable-axfr=no');
l.add('# disable-tcp=no');
l.add('# distributor-threads=3');
l.add('# fancy-records=no');
l.add('guardian=yes');
l.add('launch=ldap');
l.add('lazy-recursion=yes');
l.add('# load-modules=');
l.add('local-address=0.0.0.0');
l.add('#'+iplist);
l.add('# local-ipv6=');
l.add('local-port=53');
l.add('log-dns-details=on');
l.add('log-failed-updates=on');
l.add('logfile=/var/log/pdns.log');
l.add('# logging-facility=');
l.add('loglevel='+IntToStr(loglevel));
l.add('# master=no');
l.add('# max-queue-length=5000');
l.add('# max-tcp-connections=10');
l.add('module-dir=/usr/lib/powerdns');
l.add('# negquery-cache-ttl=60');
l.add('out-of-zone-additional-processing=yes');
l.add('# query-cache-ttl=20');
l.add('query-logging=yes');
l.add('# queue-limit=1500');
l.add('# receiver-threads=1');
l.add('# recursive-cache-ttl=10');
l.add('recursor=127.0.0.1:1553');        //
l.add('#setgid=pdns');
l.add('#setuid=pdns');
l.add('skip-cname=yes');
l.add('# slave=no');
l.add('# slave-cycle-interval=60');
l.add('# smtpredirector=a.misconfigured.powerdns.smtp.server');
l.add('# soa-minimum-ttl=3600');
l.add('# soa-refresh-default=10800');
l.add('# soa-retry-default=3600');
l.add('# soa-expire-default=604800');
l.add('# soa-serial-offset=0');
l.add('socket-dir=/var/run/pdns');
l.add('# strict-rfc-axfrs=no');
l.add('# urlredirector=127.0.0.1');
l.add('use-logfile=yes');
l.add('webserver=yes');
l.add('webserver-address=127.0.0.1');
l.add('webserver-password=');
l.add('webserver-port=8081');
l.add('webserver-print-arguments=no');
l.add('# wildcard-url=no');
l.add('# wildcards=');
l.add('version-string=powerdns');

if ldapserver='127.0.0.1' then localldap:=true;
if ldapserver='localhost' then localldap:=true;


if not localldap then l.add('ldap-host='+ldapserver+':'+zldap.ldap_settings.Port+'');


   l.add('ldap-basedn=ou=dns,'+zldap.ldap_settings.suffix);


if not localldap then begin
   l.add('ldap-binddn="cn='+zldap.ldap_settings.admin+','+zldap.ldap_settings.suffix+'"');
   l.add('ldap-secret="'+zldap.ldap_settings.password+'"');
end;

l.add('ldap-method=simple');
forceDirectories('/etc/powerdns/pdns.d');
logs.WriteToFile(l.Text,'/etc/powerdns/pdns.conf');
logs.DebugLogs('Starting......: PowerDNS updating /etc/powerdns/pdns.conf done...');
//http://wiki.debian.org/LDAP/PowerDNSSetup
//http://fxp0.org.ua/2006/sep/21/powerdns-ldap-backend-setup/
//dhcp3-server-ldap
//http://wiki.debian.org/DebianEdu/LdapifyServices
l.clear;


if not localldap then l.add('ldap-host='+ldapserver+':'+zldap.ldap_settings.Port+'');
l.add('ldap-basedn=ou=dns,'+zldap.ldap_settings.suffix);

if not localldap then begin
   l.add('ldap-binddn="cn='+zldap.ldap_settings.admin+','+zldap.ldap_settings.suffix+'"');
   l.add('ldap-secret="'+zldap.ldap_settings.password+'"');
end;

l.add('ldap-method=simple');
l.add('recursor=127.0.0.1:1553');
logs.WriteToFile(l.Text,'/etc/powerdns/pdns.d/pdns.local');
logs.DebugLogs('Starting......: PowerDNS updating /etc/powerdns/pdns.d/pdns.local done...');
L.Clear;
l.add('local-address=127.0.0.1');
l.add('quiet=no');
l.add('config-dir=/etc/powerdns/');
l.add('daemon=yes');
l.add('local-port=1553');
l.add('log-common-errors=yes');
l.add('allow-from='+cdirlist);
l.add('socket-dir=/var/run/pdns');
logs.WriteToFile(l.Text,'/etc/powerdns/recursor.conf');
logs.DebugLogs('Starting......: PowerDNS updating /etc/powerdns/recursor.conf done...');





l.free;
end;


end.
