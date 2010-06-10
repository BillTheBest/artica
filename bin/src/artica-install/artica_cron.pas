unit artica_cron;

{$MODE DELPHI}
{$LONGSTRINGS ON}

interface

uses
    Classes, SysUtils,variants,strutils,IniFiles, Process,md5,logs,unix,RegExpr in 'RegExpr.pas',zsystem,postfix_class,kas3,isoqlog,squid,fetchmail;



  type
  tcron=class


private
     LOGS:Tlogs;
     D:boolean;
     SYS:TSystem;
     artica_path:string;
     inif:TiniFile;
     EnableMilterSpyDaemon:integer;
     RetranslatorEnabled:integer;
     RetranslatorCronMinutes:integer;
     IsoQlogRetryTimes:integer;
     isoqlog:tisoqlog;
     function ARTICA_VERSION():string;
     procedure save_cyrus_backup();
     procedure save_cyrus_scan();
public
    procedure   Free;
    constructor Create(const zSYS:Tsystem);
    procedure   START();
    function    PID_NUM():string;
    procedure   STOP();
    procedure   Save_processes();
    procedure   Save_processes_watchdog();
    function    FCRON_VERSION():string;
    procedure   WATCHDOG_START();
    function    WATCHDOG_PID_NUM():string;
    procedure   STOP_WATCHDOG();
    function    STATUS():string;
    procedure   quarantine_report_schedules();


END;

implementation

constructor tcron.Create(const zSYS:Tsystem);
begin
       forcedirectories('/etc/artica-postfix');
       LOGS:=tlogs.Create();
       SYS:=zSYS;
EnableMilterSpyDaemon:=0;
RetranslatorEnabled:=0;
RetranslatorCronMinutes:=60;
IsoQlogRetryTimes:=30;

isoqlog:=tisoqlog.Create(SYS);

if not TryStrToInt(SYS.GET_INFO('RetranslatorEnabled'),RetranslatorEnabled) then RetranslatorEnabled:=0;
if not TryStrToInt(SYS.GET_INFO('RetranslatorCronMinutes'),RetranslatorCronMinutes) then RetranslatorCronMinutes:=60;
if not TryStrToInt(SYS.GET_INFO('EnableMilterSpyDaemon'),EnableMilterSpyDaemon) then EnableMilterSpyDaemon:=0;
if not TryStrToInt(SYS.GET_INFO('IsoQlogRetryTimes'),IsoQlogRetryTimes) then IsoQlogRetryTimes:=30;


       if not DirectoryExists('/usr/share/artica-postfix') then begin
              artica_path:=ParamStr(0);
              artica_path:=ExtractFilePath(artica_path);
              artica_path:=AnsiReplaceText(artica_path,'/bin/','');

      end else begin
          artica_path:='/usr/share/artica-postfix';
      end;
end;
//##############################################################################
procedure tcron.free();
begin
    logs.Free;
    isoqlog.Free;
end;
//##############################################################################
function tcron.PID_NUM():string;
var pid:string;
begin
     pid:=SYS.GET_PID_FROM_PATH('/var/run/artica-postfix.pid');
     if not SYS.PROCESS_EXIST(pid) then pid:=SYS.PIDOF_PATTERN('/usr/share/artica-postfix/bin/artica-cron.+?artica-cron.conf');
     result:=pid;
end;
//##############################################################################
function tcron.WATCHDOG_PID_NUM():string;
var pid:string;
begin
     pid:=SYS.GET_PID_FROM_PATH('/var/run/artica-watchdog.pid');
     if not SYS.PROCESS_EXIST(pid) then pid:=SYS.PIDOF_PATTERN('/usr/share/artica-postfix/bin/artica-cron.+?watchdog.conf');
     result:=pid;
end;
//##############################################################################
procedure tcron.START();
var
   l:TstringList;
   pid:string;
   parms:string;
   count:integer;
   kas3:tkas3;
   mem:integer;
   processNumber:integer;
   cpunum:integer;
   systemForkProcessesNumber:integer;
begin
  WATCHDOG_START();
  pid:=PID_NUM();
  processNumber:=1;
  if not  TryStrToInt(SYS.GET_INFO('systemForkProcessesNumber'),systemForkProcessesNumber) then systemForkProcessesNumber:=0;
  count:=0;


  if not SYS.TEST_IONICE() then begin
      logs.DebugLogs('Starting......: it seems that ionice failed, artica will not use ionice');
      SYS.set_INFO('useIonice','0');
  end;


   if SYS.PROCESS_EXIST(pid) then begin
      logs.DebugLogs('Starting......: artica-postfix daemon (fcron) is already running using PID ' + pid + '...');
      exit;
   end;
   
  kas3:=tkas3.Create(SYS);
  kas3.CHANGE_CRONTAB();
   
   
  logs.DebugLogs('Starting......: artica-postfix daemon (fcron)');
  fpsystem('/bin/rm -rf /etc/artica-postfix/spool');
  forceDirectories('/etc/artica-cron/spool');
  forceDirectories('/usr/share/artica-cron');
  l:=Tstringlist.Create;
  l.Add('fcrontabs=/etc/artica-cron/spool');
  l.Add('pidfile=/var/run/artica-postfix.pid');
  l.Add('fifofile=/etc/artica-cron/artica-postfix.fifo');
  l.Add('fcronallow=/etc/artica-cron/artica-postfix.allow');
  l.Add('fcrondeny=/etc/artica-cron/artica-postfix.deny');
  l.Add('shell=/bin/sh');
  l.SaveToFile('/etc/artica-cron/artica-cron.conf');
  l.SaveToFile('/etc/artica-cron/fcron.conf');

  logs.DebugLogs('Starting......: artica-postfix creating crond.d/artica-cron watchdog daemon...');
  SYS.CRON_CREATE_SCHEDULE('5,10,15,20,25,30,35,40,45,50,55,59 * * * *',artica_path+ '/bin/artica-install -watchdog daemon','artica-cron');

  l.free;
  fpsystem('/bin/chown root:root /etc/artica-cron/artica-cron.conf');
  fpsystem('/bin/chown root:root /etc/artica-cron/fcron.conf');
  fpsystem('/bin/chown -R root:root /etc/artica-cron/spool');
  fpsystem('/bin/chmod 600 /etc/artica-cron/artica-cron.conf');
  fpsystem('/bin/chmod 600 /etc/artica-cron/fcron.conf');

  mem:=SYS.MEM_TOTAL_INSTALLEE();
  cpunum:=SYS.CPU_NUMBER();
  if mem=0 then mem:=516300;
  // 256 = 255436
  // 512 = 516300
  // 1G = 1002252

if systemForkProcessesNumber=0 then begin
  if mem>255436 then begin
      if cpunum<2 then processNumber:=1;
  end;

   if mem>516300 then begin
      processNumber:=3;
      if cpunum<2 then processNumber:=1;
  end;

   if mem>1002252 then begin
      processNumber:=4;
      if cpunum<2 then processNumber:=2;
  end;

  if mem>2004504 then begin
     processNumber:=6;
     if cpunum<4 then processNumber:=4;
  end;
  if processNumber>4 then processNumber:=4;

  SYS.SET_INFO('systemForkProcessesNumber',IntToStr(processNumber))

end else begin
   processNumber:=systemForkProcessesNumber;
end;



  parms:=artica_path + '/bin/artica-cron --configfile /etc/artica-cron/artica-cron.conf --background --savetime 1800 --maxserial '+intToStr(processNumber)+' --firstsleep 10';
  Save_processes();

  logs.DebugLogs('Starting......: artica-postfix daemon (fcron) CPU(s):'+IntToStr(cpunum)+' Memory:'+IntTOstr(round(mem div 1024))+' Mb');
  logs.DebugLogs('Starting......: artica-postfix daemon (fcron) ' + intToStr(processNumber)+' processe(s) number at the same time');
  logs.OutputCmd(SYS.EXEC_NICE()+artica_path + '/bin/artica-ldap -syncmodules &');
  logs.OutputCmd(SYS.EXEC_NICE()+artica_path + '/bin/artica-iso &');
  
  logs.OutputCmd(parms);
  logs.DebugLogs('tcron.START(): delete root config');
  logs.DeleteFile('/etc/artica-cron/spool/root');
  
  while not SYS.PROCESS_EXIST(PID_NUM()) do begin
        sleep(500);
        count:=count+1;
        logs.DebugLogs('tcron.START(): wait sequence ' + intToStr(count));
        if count>20 then begin
            logs.DebugLogs('Starting......: artica-postfix daemon (fcron) failed...');
            exit;
        end;
  end;
  logs.DebugLogs('Starting......: Installing crontab');
  logs.OutputCmd(artica_path + '/bin/fcrontab -c /etc/artica-cron/artica-cron.conf -z root');
  logs.Syslogs('Success starting artica-cron daemon...');
  logs.DebugLogs('Starting......: artica-postfix daemon (fcron) success...');

end;
//##############################################################################
procedure tcron.WATCHDOG_START();
var
   l:TstringList;
   pid:string;
   parms:string;
   count:integer;
begin

  pid:=WATCHDOG_PID_NUM();
  count:=0;
   if SYS.PROCESS_EXIST(pid) then begin
      logs.DebugLogs('Starting......: artica-postfix daemon watchdog (fcron) is already running using PID ' + pid + '...');
      exit;
   end;
  fpsystem('/bin/rm -rf /etc/artica-cron/spool_watchdog/*');
  forceDirectories('/etc/artica-cron/spool_watchdog');
  l:=Tstringlist.Create;
  l.Add('fcrontabs=/etc/artica-cron/spool_watchdog');
  l.Add('pidfile=/etc/artica-cron/artica-watchdog.pid');
  l.Add('fifofile=/etc/artica-cron/artica-watchdog.fifo');
  l.Add('fcronallow=/etc/artica-cron/artica-watchdog.allow');
  l.Add('fcrondeny=/etc/artica-cron/artica-watchdog.deny');
  l.Add('shell=/bin/sh');
  l.SaveToFile('/etc/artica-cron/artica-watchdog.conf');
  l.SaveToFile('/etc/artica-cron/watchdog.conf');
  l.free;

  fpsystem('/bin/chown root:root /etc/artica-cron/watchdog.conf');
  fpsystem('/bin/chown -R root:root /etc/artica-cron/spool_watchdog');
  fpsystem('/bin/chmod 644 /etc/artica-cron/artica-watchdog.conf');



  parms:=artica_path + '/bin/artica-cron --background --savetime 1800 --maxserial 5 --firstsleep 10 --configfile /etc/artica-cron/artica-watchdog.conf';
  Save_processes_watchdog();
  logs.DebugLogs('Starting......: artica-postfix daemon watchdog (fcron)');
  logs.OutputCmd(parms);
  logs.DebugLogs('tcron.WATCHDOG_START(): delete root config');
  logs.DeleteFile('/etc/artica-cron/spool_watchdog/root');

  while not SYS.PROCESS_EXIST(WATCHDOG_PID_NUM()) do begin
        sleep(500);
        count:=count+1;
        logs.DebugLogs('tcron.START(): wait sequence ' + intToStr(count));
        if count>20 then begin
            logs.DebugLogs('Starting......: artica-postfix daemon watchdog (fcron) failed...');
            logs.DebugLogs('Starting......: '+parms);
            exit;
        end;
  end;
  logs.DebugLogs('Starting......: Installing watchdog crontab');
  fpsystem('/bin/chmod 644 /etc/artica-cron/artica-watchdog.conf');
  fpsystem('/bin/chmod 644 /etc/artica-cron/watchdog.conf');
  fpsystem('/bin/chown root:root /etc/artica-cron/artica-watchdog.conf');
  fpsystem(artica_path + '/bin/fcrontab -z root -c /etc/artica-cron/watchdog.conf >/tmp/watchdog.tmp');
  logs.DebugLogs('Starting......: artica-postfix daemon watchdog ' + logs.ReadFromFile('/tmp/watchdog.tmp'));
  logs.Syslogs('Success starting artica-cron watchdog daemon...');
  logs.DebugLogs('Starting......: artica-postfix daemon watchdog (fcron) success...');
end;
//##############################################################################
procedure tcron.STOP_WATCHDOG();
var
   pid:string;
   count:integer;
begin
pid:=PID_NUM();
count:=0;
if SYS.PROCESS_EXIST(WATCHDOG_PID_NUM()) then begin
   writeln('Stopping artica-cron watchdog (fcron).: ' + pid + ' PID..');
   fpsystem('/bin/kill ' + pid);
end;
  while SYS.PROCESS_EXIST(WATCHDOG_PID_NUM()) do begin
        sleep(100);
        count:=count+1;
        if count>20 then begin
            fpsystem('/bin/kill -9 ' + WATCHDOG_PID_NUM());
            break;
        end;
  end;
pid:=SYS.AllPidsByPatternInPath('bin/artica-cron --background');
if length(pid)>0 then begin
   writeln('Stopping artica-cron watchdog (fcron).: '+ pid + '...');
   fpsystem('/bin/kill ' + pid);
end;

logs.Syslogs('Stopping artica-cron watchdog (fcron).: success...');
writeln('Stopping artica-cron watchdog (fcron).: success...');
logs.NOTIFICATION('[ARTICA]:('+sys.HOSTNAME_g()+') Artica watchdog daemon was stopped !!','','system');
end;

//#############################################################################


procedure tcron.STOP();
var
   pid:string;
   count:integer;
begin
pid:=PID_NUM();
count:=0;
if SYS.PROCESS_EXIST(pid) then begin
   writeln('Stopping artica-cron (fcron).: ' + pid + ' PID..');
   fpsystem('/bin/kill ' + pid);
end;





  while SYS.PROCESS_EXIST(PID_NUM()) do begin
        sleep(100);
        count:=count+1;
        if count>20 then begin
            fpsystem('/bin/kill -9 ' + pid);
            break;
        end;
  end;
pid:=SYS.AllPidsByPatternInPath('bin/artica-cron --background');
if length(pid)>0 then begin
   writeln('Stopping artica-cron (fcron).: '+ pid + '...');
   fpsystem('/bin/kill ' + pid);
end;

logs.Syslogs('Stopping artica-cron (fcron).: success...');
writeln('Stopping artica-cron (fcron).: success...');


   
end;

//##############################################################################
procedure tcron.Save_processes();

var l:TstringList;
cmd_prepend,tmp:string;
Nice:integer;
Nicet:string;
cmdnice:string;
nolog:string;
backup_time:string;
backup_min:string;
backup_hour:string;
backup_min_int:Integer;
backup_hour_int:Integer;
backup_command:string;
backup_command2:string;
schedule_time:string;
backups:Tstringlist;
RegExpr:TRegExpr;
ini:TiniFile;
postfix:tpostfix;
WBLReplicEachMin:string;
SalearnSchedule:string;
i:integer;
systemMaxOverloaded:integer;
squid:Tsquid;
WifiAPEnable:integer;
EnableFetchmail:integer;
fetchmail:tfetchmail;
begin
      nolog:=',nolog(true)';
      l:=TstringList.Create;
      backup_command:='';
      postfix:=tpostfix.Create(SYS);
       if not TryStrToInt(SYS.GET_INFO('EnableFetchmail'),EnableFetchmail) then EnableFetchmail:=0;

      tmp:=SYS.GET_PERFS('ProcessNice');
      if not TryStrToInt(tmp,Nice) then Nice:=19;
      Nicet:='nice('+IntToStr(Nice)+'),mail(false)';
      cmdnice:=SYS.EXEC_NICE();
      logs.DeleteFile('/etc/cron.d/artica.cron.backups');
      logs.DeleteFile('/etc/cron.d/artica.cron.backup');
      logs.DeleteFile('/etc/cron.d/artica-cron-backup');
      logs.DeleteFile('/etc/cron.d/artica-cron-dansguardian');
      logs.DeleteFile('/etc/cron.d/artica-isoqlog');
      logs.DeleteFile('/etc/cron.d/artica-cron-sarg');
      logs.DeleteFile('/etc/cron.d/artica-cron-quarantine');
      logs.DeleteFile('/etc/cron.d/artica-cron-sharedfolders');
      logs.DeleteFile('/etc/cron.d/artica-cron-mailbackup');
      logs.DeleteFile('/etc/cron.d/artica-cron-mysqldb');
logs.DeleteFile('/etc/cron.d/artica-cron-urgency');
logs.DeleteFile('/etc/cron.d/artica-cron-orders');
logs.DeleteFile('/etc/cron.d/artica-cron-quar-disk');
logs.DeleteFile('/etc/cron.d/artica-cron-executor-0');
logs.DeleteFile('/etc/cron.d/artica-cron-cups-drv');
logs.DeleteFile('/etc/cron.d/artica-isoqlog');
logs.DeleteFile('/etc/cron.d/artica-cron-orgstats');
logs.DeleteFile('/etc/cron.d/artica-cron-process1f');
logs.DeleteFile('/etc/cron.d/artica-watch-queue');
logs.DeleteFile('/etc/cron.d/artica-cron-watchdog');
logs.DeleteFile('/etc/cron.d/artica-cron-spamblacklists');
logs.DeleteFile('/etc/cron.d/artica-cron-executor-120');
logs.DeleteFile('/etc/cron.d/artica-cron-postfixiptables');
logs.DeleteFile('/etc/cron.d/artica-cron-status');
logs.DeleteFile('/etc/cron.d/artica-cron-buildhomes');
logs.DeleteFile('/etc/cron.d/artica-cron-adminstatus1');
logs.DeleteFile('/etc/cron.d/artica-cron-process1k');
logs.DeleteFile('/etc/cron.d/artica-cron-postfixloggerflow');
logs.DeleteFile('/etc/cron.d/artica-cron-patchs');
logs.DeleteFile('/etc/cron.d/artica-cron-clamvupd');
logs.DeleteFile('/etc/cron.d/artica-cron-mysqlq');
logs.DeleteFile('/etc/cron.d/artica-clean-smtplogs');
logs.DeleteFile('/etc/cron.d/artica-cron-mailarchive');
logs.DeleteFile('/etc/cron.d/artica-cron-exec');
logs.DeleteFile('/etc/cron.d/artica-cron-vacation');
logs.DeleteFile('/etc/cron.d/artica-cron-apt');
logs.DeleteFile('/etc/cron.d/artica-cron-quarantines');
logs.DeleteFile('/etc/cron.d/artica-cron-notifs');
logs.DeleteFile('/etc/cron.d/artica-cron-checkvirusqueue');
logs.DeleteFile('/etc/cron.d/artica-cron-parse-dar');
logs.DeleteFile('/etc/cron.d/artica-cron-awstats');
logs.DeleteFile('/etc/cron.d/artica-cron-executor-5');
logs.DeleteFile('/etc/cron.d/artica-remoteinstall');
logs.DeleteFile('/etc/cron.d/artica-cron-executor-2');
logs.DeleteFile('/etc/cron.d/artica-cron-backcyrus0');
logs.DeleteFile('/etc/cron.d/artica-cron-syncmodules');
logs.DeleteFile('/etc/cron.d/artica-cron-geoip');
logs.DeleteFile('/etc/cron.d/artica-cron-cyrusav');
logs.DeleteFile('/etc/cron.d/artica-cron-executor-10');
logs.DeleteFile('/etc/cron.d/artica-cron-process1');
logs.DeleteFile('/etc/cron.d/artica-squidRRD0');
logs.DeleteFile('/etc/cron.d/artica-process1');
logs.DeleteFile('/etc/cron.d/artica-cron-smtplastmails');
logs.DeleteFile('/etc/cron.d/artica-cron-fetchsql');
logs.DeleteFile('/etc/cron.d/artica-cron-sarg');
logs.DeleteFile('/etc/cron.d/artica-cron-postfixlogger');
logs.DeleteFile('/etc/cron.d/artica-cron-topcpumem');
logs.DeleteFile('/etc/cron.d/artica-cron-mailgraph');
logs.DeleteFile('/etc/cron.d/artica-cron-backcyrus2');
logs.DeleteFile('/etc/cron.d/artica-cron-adminsmtpflow');
logs.DeleteFile('/etc/cron.d/artica-cron-adminstatus2');
logs.DeleteFile('/etc/cron.d/artica-cron-iso');
logs.DeleteFile('/etc/cron.d/artica-cron-rsynclogs');
logs.DeleteFile('/etc/cron.d/artica-cron-update');
logs.DeleteFile('/etc/cron.d/artica-cron-wblphp');
logs.DeleteFile('/etc/cron.d/artica-cron-executor-300');

      SYS.DirFiles('/etc/cron.d','*');
      for i:=0 to l.Count-1 do begin
          writeln('Uninstall schedule ' + l.Strings[i]);


      end;


      if not TryStrToInt(SYS.GET_INFO('systemMaxOverloaded'),systemMaxOverloaded) then begin
         SYS.isoverloadedTooMuch();
             if not TryStrToInt(SYS.GET_INFO('systemMaxOverloaded'),systemMaxOverloaded) then begin
                  systemMaxOverloaded:=(SYS.CPU_NUMBER()+2)*2;
             end;
      end;

      if systemMaxOverloaded<2 then systemMaxOverloaded:=6;

      logs.DebugLogs('Starting......: Daemon (fcron) tasks will be stopped if load is up to '+INtTOStr(systemMaxOverloaded));

      if FileExists('/etc/artica-postfix/artica-backup.conf') then begin
         ini:=TiniFile.Create('/etc/artica-postfix/artica-backup.conf');
          logs.DebugLogs('tcron.Save_processes() get ArticaBackupEnabled configuration');
         if SYS.GET_INFO('ArticaBackupEnabled')='1' then begin
            backup_time:=ini.ReadString('backup','backup_time','03:00');
            RegExpr:=TRegExpr.Create;
            RegExpr.Expression:='([0-9]+):([0-9]+)';


            if RegExpr.Exec(backup_time) then begin
               backup_hour:=RegExpr.Match[1];
               backup_min:=RegExpr.Match[2];
               if not TryStrToInt(backup_hour,backup_hour_int) then begin
                     logs.DebugLogs('Starting......: Daemon (cron) failed to int ' + backup_hour + '(assume 3)');
                     backup_hour_int:=3;
               end;

               if not TryStrToInt(backup_min,backup_min_int) then begin
                     logs.DebugLogs('Starting......: Daemon (cron) failed to int ' + backup_min + '(assume 0)');
                     backup_min_int:=0;
               end;

               logs.DebugLogs('Starting......: Daemon (cron) backup time every day at '+IntToStr(backup_hour_int) +'h'+IntToStr(backup_min_int)+'mn');
               SYS.CRON_CREATE_SCHEDULE(IntToStr(backup_min_int)+' '+IntToStr(backup_hour_int)+' * * * ',cmdnice+artica_path+'/bin/artica-backup --backup >/dev/null 2>&1','artica-cron-backup');
            end;

         end;
      end;


      if FileExists('/etc/cron.d/artica-cron-pflogsumm') then logs.DeleteFile('/etc/cron.d/artica-cron-pflogsumm');

      if FileExists('/etc/artica-postfix/settings/Daemons/pflogsumm') then begin
           ini:=TiniFile.Create('/etc/artica-postfix/settings/Daemons/pflogsumm');
           schedule_time:=ini.ReadString('SETTINGS','schedule','');
           if length(schedule_time)>0 then begin
             logs.DebugLogs('Starting......: Daemon (cron) set pflogsumm reports schedule...');
             SYS.CRON_CREATE_SCHEDULE(schedule_time,cmdnice+SYS.LOCATE_PHP5_BIN() +' '+artica_path+'/exec.postfix.reports.php','artica-cron-pflogsumm');
           end;
      end;

      l.Add('!mailto(root)');
      l.add('!serial(true),b(0)');
      if length(backup_command)>0 then begin
          l.Add(backup_command);
      end;
      l.Add('@'+Nicet+nolog+',lavg1('+IntToStr(systemMaxOverloaded)+') 10s '+cmdnice+SYS.LOCATE_PHP5_BIN()+ ' ' +artica_path+'/exec.parse-orders.php');
      l.Add('@'+Nicet+nolog+',lavg1('+IntToStr(systemMaxOverloaded)+') 12s '+cmdnice+SYS.LOCATE_PHP5_BIN()+ ' ' +artica_path+'/exec.executor.php --group10s');
      l.Add('@'+Nicet+nolog+',lavg1('+IntToStr(systemMaxOverloaded)+') 30s '+cmdnice+SYS.LOCATE_PHP5_BIN()+ ' ' +artica_path+'/exec.executor.php --group30s');


// ---------------------------------- fetchmail ---------------------------------------------------------------------------------------------------------
      fetchmail:=tfetchmail.Create(SYS);
      if FileExists(fetchmail.FETCHMAIL_BIN_PATH()) then begin
         logs.DebugLogs('Starting......: Daemon (fcron) set fetchmail injector schedule');
         l.Add('@'+Nicet+',lavg1('+IntToStr(systemMaxOverloaded)+') 2 '+cmdnice+SYS.LOCATE_PHP5_BIN()+ ' ' +artica_path+'/exec.fetchmail.sql.php');
      end;
      fetchmail.free;
// -------------------------------------------------------------------------------------------------------------------------------------------------------


      squid:=Tsquid.Create;
      if FileExists(squid.SQUID_BIN_PATH()) then begin
         logs.DebugLogs('Starting......: Daemon (fcron) set squid injector reports schedule...');
         l.Add('@'+Nicet+nolog+',lavg1('+IntToStr(systemMaxOverloaded)+') 58s '+cmdnice+SYS.LOCATE_PHP5_BIN()+ ' ' +artica_path+'/exec.dansguardian.injector.php');
      end else begin
         logs.DebugLogs('Starting......: Daemon (fcron) Squid is not installed');
      end;

     squid.free;

// ---------------------------------- BACKUP ---------------------------------------------------------------------------------------------------------

      fpsystem(SYS.LOCATE_PHP5_BIN()+' /usr/share/artica-postfix/exec.backup.php --no-reload');
      if FileExists('/etc/artica-postfix/backup.tasks') then begin
          backups:=Tstringlist.Create;
          try
             backups.LoadFromFile('/etc/artica-postfix/backup.tasks');
             for i:=0 to backups.Count-1 do begin
                  l.Add(backups.Strings[i]);
             end;
          except
            logs.DebugLogs('Starting......: Daemon (cron) Error set backup tasks');
          end;
          logs.DebugLogs('Starting......: Daemon (cron) set ' +IntToStr(backups.Count)+' backup tasks');
          backups.free;
      end;

// -------------------------------------------------------------------------------------------------------------------------------------------

      SYS.DirFiles('/etc/artica-postfix/ad-import','import-ad-*');
      for i:=0 to SYS.DirListFiles.Count-1 do begin
          logs.DebugLogs('Starting......: Daemon (cron) importing Active Directory task '+ SYS.DirListFiles.Strings[i]);
          l.Add(trim(logs.ReadFromFile('/etc/artica-postfix/ad-import/'+SYS.DirListFiles.Strings[i])));
      end;

// ---------------------------------- WIFI ---------------------------------------------------------------------------------------------------------
if not TryStrToInt(SYS.GET_INFO('WifiAPEnable'),WifiAPEnable) then WifiAPEnable:=0;
if WifiAPEnable=1 then begin
      logs.DebugLogs('Starting......: Daemon (cron) Activate WIFI Client connection watchdog');
      l.Add('@'+Nicet+',lavg1('+IntToStr(systemMaxOverloaded)+') 5 '+cmdnice+SYS.LOCATE_PHP5_BIN()+ ' ' +artica_path+'/exec.wifi.detect.cards.php --checkap');
end;

l.add('@first(1),lavg1('+IntToStr(systemMaxOverloaded)+') 10   /etc/init.d/artica-postfix start all');


      if EnableMilterSpyDaemon=1 then begin
           logs.DebugLogs('Starting......: artica-postfix daemon (fcron) enable mailspy statistics');
           if FileExists('/usr/local/bin/cronspy.sh') then begin
              fpsystem('/bin/chmod 777 /usr/local/bin/cronspy.sh');
              l.Add('@'+Nicet+' 15 /usr/local/bin/cronspy.sh hourly');
              l.Add('@'+Nicet+' 5h /usr/local/bin/cronspy.sh daily');
              l.Add('@'+Nicet+' 10h /usr/local/bin/cronspy.sh weekly');
           end;
      end;
      



      if RetranslatorEnabled=1 then begin
           logs.DebugLogs('Starting......: artica-postfix daemon (fcron) enable kaspersky retranslator each '+IntToStr(RetranslatorCronMinutes)+' minutes');
           l.Add('@'+Nicet+' '+IntToStr(RetranslatorCronMinutes) +' '+ artica_path+'/bin/artica-update --retranslator');
      end;

      //tous les 5 jours � 2H30�
      SYS.CRON_CREATE_SCHEDULE('30 2 1,5,10,15,20,30 * *','/usr/share/artica-postfix/bin/artica-make APP_CLAMAV','artica-cron-clamvupd');

      //A 23h00
      //SYS.CRON_CREATE_SCHEDULE('0 23 * * *',cmdnice+artica_path+'/bin/artica-install --dansguardian-stats','artica-cron-dansguardian');

      //A 2H
      SYS.CRON_CREATE_SCHEDULE('0 2 * * *',cmdnice+SYS.LOCATE_PHP5_BIN()+ ' ' +artica_path+'/exec.smtp.events.clean.php','artica-clean-smtplogs');

      //toutes les heures
      SYS.CRON_CREATE_SCHEDULE('@hourly',cmdnice+artica_path+'/bin/artica-update','artica-cron-update');
      SYS.CRON_CREATE_SCHEDULE('@hourly',cmdnice+SYS.LOCATE_PHP5_BIN()+ ' ' +artica_path+'/cron.mysql-databases.php','artica-cron-mysqldb');
      SYS.CRON_CREATE_SCHEDULE('@hourly',cmdnice+SYS.LOCATE_PHP5_BIN()+ ' ' +artica_path+'/exec.vacationtime.php','artica-cron-vacation');

      if FileExists('/usr/bin/sarg') then begin
         SYS.CRON_CREATE_SCHEDULE('@hourly',artica_path+'/bin/artica-install --sarg','artica-cron-sarg');
      end;



      //toutes les deux heures
      SYS.CRON_CREATE_SCHEDULE('0 2,4,6,8,10,12,14,16,18,20,22 * * *',cmdnice+SYS.LOCATE_PHP5_BIN()+ ' ' +artica_path+'/exec.executor.php --group120','artica-cron-executor-120');


      //toutes les 5 Heures
      SYS.CRON_CREATE_SCHEDULE('0 5,10,15,20 * * *',cmdnice+SYS.LOCATE_PHP5_BIN()+ ' ' +artica_path+'/exec.executor.php --group300','artica-cron-executor-300');

      //toutes les 30 Minutes
      SYS.CRON_CREATE_SCHEDULE('0,30 * * * *',cmdnice+artica_path+'/bin/artica-install --verify-artica-iso','artica-cron-iso'); //iso
      if FileExists(isoqlog.BIN_PATH()) then SYS.CRON_CREATE_SCHEDULE('0,30 * * * *',cmdnice+artica_path+'/bin/artica-install --isoqlog','artica-isoqlog');

      //toutes les 20 Minutes
      SYS.CRON_CREATE_SCHEDULE('0,20,40 * * * *',cmdnice+artica_path+'/bin/process1 --kill','artica-cron-process1k');  //watchdog kill

      //toutes les 10 minutes
      SYS.CRON_CREATE_SCHEDULE('0,10,20,30,40,50 * * * *',cmdnice+SYS.LOCATE_PHP5_BIN()+ ' ' +artica_path+'/exec.executor.php --group10','artica-cron-executor-10');


      //toutes les 5 minutes
      SYS.CRON_CREATE_SCHEDULE('0,5,10,15,20,25,30,35,40,45,50,55 * * * *',cmdnice+SYS.LOCATE_PHP5_BIN()+ ' ' +artica_path+'/exec.executor.php --group5','artica-cron-executor-5');
      SYS.CRON_CREATE_SCHEDULE('0,5,10,15,20,25,30,35,40,45,50,55 * * * *','/etc/init.d/artica-postfix start daemon','artica-cron-watchdog');


      //toutes les 2 minutes
      SYS.CRON_CREATE_SCHEDULE('0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32,34,36,38,40,42,44,46,48,50,52,54,56,58 * * * *',cmdnice+SYS.LOCATE_PHP5_BIN()+ ' ' +artica_path+'/exec.executor.php --group2','artica-cron-executor-2');

      //toutes les minutes
      SYS.CRON_CREATE_SCHEDULE('* * * * *',cmdnice+SYS.LOCATE_PHP5_BIN()+ ' ' +artica_path+'/exec.executor.php --group0','artica-cron-executor-0');

      //specifiques
      quarantine_report_schedules();

      if FIleExists('/usr/local/ap-mailfilter3/control/bin/sfmonitoring') then begin
         logs.OutputCmd('/usr/bin/crontab -u mailflt3 -r');
         SYS.CRON_CREATE_SCHEDULE('8,28,48 * * * *',cmdnice+'/usr/local/ap-mailfilter3/bin/sfupdates -q && chown -R mailflt3:mailflt3 /usr/local/ap-mailfilter3/cfdata','artica-cron-kas3-1');
         SYS.CRON_CREATE_SCHEDULE('2,13,24,35,46,57 * * * *',cmdnice+'/usr/local/ap-mailfilter3/bin/uds-rtts.sh -q','artica-cron-kas3-2');
         SYS.CRON_CREATE_SCHEDULE('*/5 * * * *',cmdnice+'/usr/local/ap-mailfilter3/control/bin/sfmonitoring -q','artica-cron-kas3-3');
         SYS.CRON_CREATE_SCHEDULE('* * * * *',cmdnice+'/usr/local/ap-mailfilter3/control/bin/dologs.sh -q','artica-cron-kas3-4');
         SYS.CRON_CREATE_SCHEDULE('*/5 * * * *',cmdnice+'/usr/local/ap-mailfilter3/control/bin/dograph.sh -q','artica-cron-kas3-5');
         SYS.CRON_CREATE_SCHEDULE('7 */12 * * *',cmdnice+'/usr/local/ap-mailfilter3/control/bin/logrotate.sh -q','artica-cron-kas3-6');
     end;

      //cyrus
      save_cyrus_backup();
      save_cyrus_scan();


      if SYS.GET_INFO('EnableFDMFetch')='1' then begin
         logs.DebugLogs('Starting......: artica-postfix daemon (fcron) enable FDM polling every 10mn');
         l.add('@'+Nicet+' 30 '+  artica_path+'/bin/artica-ldap -fdm');
      end;



      try
      l.SaveToFile('/etc/artica-cron/spool/root.orig');
      logs.syslogs('Saving croned scripts');

      fpsystem('/bin/rm -f /etc/cron.d/artica-avcomp-*');
      fpsystem(SYS.LOCATE_PHP5_BIN()+' '+ artica_path+'/exec.rsync.events.php --computers-schedule >/dev/null &');
      fpsystem(SYS.LOCATE_PHP5_BIN()+' '+ artica_path+'/exec.computer.scan.php --schedules >/dev/null &');

      except
         logs.syslogs('Saving croned scripts failed !');
      end;
      l.free;
end;
//#########################################################################################
procedure tcron.quarantine_report_schedules();
var
   i:integer;
   RegExpr:TRegExpr;
   path:string;
   ini:TiniFile;
   ou:string;
   pattern:string;
   cmdnice:string;
begin

   RegExpr:=TRegExpr.Create;
   RegExpr.Expression:='^OuSendQuarantineReports.+';
   SYS.DirFiles('/etc/artica-postfix/settings/Daemons','*');
   cmdnice:=SYS.EXEC_NICE();

   for i:=0 to SYS.DirListFiles.Count-1 do begin
        if RegExpr.Exec(SYS.DirListFiles.Strings[i]) then begin
           path:='/etc/artica-postfix/settings/Daemons/'+SYS.DirListFiles.Strings[i];
           ini:=TiniFile.Create(path);
           ou:=ini.ReadString('NEXT','org','');
           pattern:=ini.ReadString('NEXT','cron','59 23 * * *');
           if ini.ReadInteger('NEXT','Enabled',0)=0 then begin
              if FileExists('/etc/cron.d/artica-cron-quarsched-'+ou) then begin
                 logs.Debuglogs('Starting......: uninstall artica-cron-quarsched-'+ou);
                 logs.DeleteFile('/etc/cron.d/artica-cron-quarsched-'+ou);
              end;
              continue;
           end;

           logs.DebugLogs('Starting......: Scheduled ' + ou+' organization for end-users quarantine reports');
           SYS.CRON_CREATE_SCHEDULE(pattern,cmdnice+SYS.LOCATE_PHP5_BIN()+ ' ' +artica_path+'/exec.quarantine.reports.php '+ou,'artica-cron-quarsched-'+ou);
        end;
   end;




end;
//#########################################################################################
procedure tcron.save_cyrus_backup();
var
   l:Tstringlist;
   f:Tinifile;
   i:integer;
   Sections:Tstringlist;
   schedule,cmdnice:string;
begin
    cmdnice:=SYS.EXEC_NICE();
    SYS.DirFiles('/etc/cron.d','artica-cron-backcyrus*');
    for i:=0 to  SYS.DirListFiles.Count-1 do begin
        logs.Debuglogs('Starting......: artica-postfix Daemon (cron) uninstall '+SYS.DirListFiles.Strings[i]);
        logs.DeleteFile('/etc/cron.d/'+SYS.DirListFiles.Strings[i]);
    end;


    logs.DeleteFile('/etc/cron.d/artica-cron-backcyrus');
    if not FileExists('/etc/artica-postfix/settings/Daemons/CyrusBackupRessource') then exit;
    f:=tinifile.Create('/etc/artica-postfix/settings/Daemons/CyrusBackupRessource');
    Sections:=Tstringlist.Create;
    f.ReadSections(Sections);
    for i:=0 to  Sections.Count-1 do begin
       if length(trim(Sections.Strings[i]))=0 then continue;
       schedule:=f.ReadString(Sections.Strings[i],'schedule','');
       if length(trim(schedule))=0 then continue;
       logs.Debuglogs('Starting......: artica-postfix Daemon (cron) install artica-cron-backcyrus'+IntTostr(i));
       SYS.CRON_CREATE_SCHEDULE(schedule,cmdnice+'/usr/share/artica-postfix/bin/artica-backup --single-cyrus "'+Sections.Strings[i]+'"','artica-cron-backcyrus'+IntTostr(i));
    end;

    f.free;
    Sections.free;
end;
//#########################################################################################
procedure tcron.save_cyrus_scan();
var
   CyrusEnableAV:integer;
   inif:TiniFile;
   Schedule:string;
begin
    logs.DeleteFile('/etc/cron.d/artica-cron-cyrusav');
    CyrusEnableAV:=0;
    if not TryStrToInt(SYS.GET_INFO('CyrusEnableAV'),CyrusEnableAV) then CyrusEnableAV:=0;
    if CyrusEnableAV=0 then exit;
    if not FileExists('/etc/artica-postfix/settings/Daemons/CyrusAVConfig') then exit;
    inif:=TiniFile.Create('/etc/artica-postfix/settings/Daemons/CyrusAVConfig');
    Schedule:=inif.ReadString('SCAN','schedule','');
    if length(trim(Schedule))=0 then exit;
    SYS.CRON_CREATE_SCHEDULE(Schedule,'/usr/share/artica-postfix/bin/artica-install --scan-cyrus','artica-cron-cyrusav');
    inif.free;
end;
//#########################################################################################


procedure tcron.Save_processes_watchdog();
var l:TstringList;
cmd_prepend,tmp:string;
Nice:integer;
Nicet:string;
nolog:string;
postfix:tpostfix;
WBLReplicEachMin:string;
SalearnSchedule:string;
RegExpr:TRegExpr;
begin


postfix:=Tpostfix.Create(SYS);
      nolog:=',nolog(true)';
      l:=TstringList.Create;
      tmp:=SYS.GET_PERFS('ProcessNice');
      if not TryStrToInt(tmp,Nice) then Nice:=19;
      Nicet:='nice('+IntToStr(Nice)+'),mail(false)';
      l.Add('!mailto(root)');
      l.add('!serial(true),b(0)');



      //Quarantine croned...
      if not FileExists(SYS.LOCATE_PHP5_BIN()) then begin
         logs.Syslogs('Starting......: artica-postfix watchdog (fcron) unable to stat PHP/php5 binary !!' );
      end else begin
            l.Add('@'+Nicet+' 8h '+SYS.LOCATE_PHP5_BIN()+' '+artica_path+'/cron.quarantine.php');
      end;



      //roundcube croned....
      if not FileExists(SYS.LOCATE_PHP5_BIN()) then begin
         logs.Syslogs('Starting......: artica-postfix watchdog (fcron) unable to stat PHP/php5 binary !!' );
      end else begin
          if FileExists('/usr/share/roundcube/config/db.inc.php') then begin
             logs.DebugLogs('Starting......: artica-postfix watchdog (fcron) enable roundcube user auto-update');
             l.Add('@'+Nicet+nolog+' 30 '+  SYS.LOCATE_PHP5_BIN() + ' ' + artica_path+'/exec.roundcube.php');
             l.Add('@'+Nicet+nolog+' 3h '+  SYS.LOCATE_PHP5_BIN() + ' ' + artica_path+'/cron.endoflife.php');
          end;
      end;

      //obm croned....
      tmp:=SYS.GET_INFO('OBMSyncCron');
      if length(tmp)=0 then tmp:='2h';
      if DirectoryExists(SYS.LOCATE_OBM_SHARE()) then begin
         RegExpr:=TRegExpr.CReate();
         RegExpr.Expression:='([0-9]+)(m|h|d)';
         if RegExpr.Exec(tmp) then begin
            if RegExpr.Match[2]='m' then begin
               l.Add('@'+Nicet+' '+RegExpr.Match[2]+' '+SYS.LOCATE_PHP5_BIN() + ' ' + artica_path+'/cron.obm.synchro.php');
            end else begin
               l.Add('@'+Nicet+' '+tmp+' '+SYS.LOCATE_PHP5_BIN() + ' ' + artica_path+'/cron.obm.synchro.php');
            end;
         end;
         logs.DebugLogs('Starting......: artica-postfix watchdog (fcron) enable OBM Sync users every '+tmp);
      end;


      try
      l.SaveToFile('/etc/artica-cron/spool_watchdog/root.orig');
      logs.syslogs('Saving watchdog croned scripts');
      except
         logs.syslogs('Saving watchdog croned scripts failed !');
      end;
      l.free;
end;
//#########################################################################################



function tcron.STATUS():string;
var ini:TstringList;
begin
ini:=TstringList.Create;

   ini.Add('[ARTICA]');
   ini.Add('monit=1');
   ini.Add('master_version=' + ARTICA_VERSION()+'/' + FCRON_VERSION);
   ini.Add('service_name=APP_ARTICA');
   ini.Add('service_cmd=daemon');
   
   ini.Add('[ARTICA_WATCHDOG]');
   ini.Add('monit=1');
   ini.Add('master_version=' + ARTICA_VERSION()+'/' + FCRON_VERSION);
   ini.Add('service_name=APP_ARTICA_WATCHDOG');

   SYS.MONIT_CONFIG('APP_ARTICA','/var/run/artica-postfix.pid','daemon');
   SYS.MONIT_CONFIG('APP_ARTICA_WATCHDOG','/etc/artica-cron/artica-watchdog.pid','daemon');
   result:=ini.Text;
   ini.free;

end;
//#########################################################################################
function tcron.FCRON_VERSION():string;
var
   l:string;
   F:TstringList;
   t:string;
   i:integer;
   RegExpr:TRegExpr;
begin

   if not FileExists(artica_path + '/bin/artica-cron') then exit('0.00');
   result:=SYS.GET_CACHE_VERSION('APP_FCRON');
   if length(result)>0 then exit;
   t:=logs.FILE_TEMP();
   fpsystem(artica_path + '/bin/artica-cron -V >' + t + ' 2>&1');
   if not FileExists(t) then exit;
   
   RegExpr:=TRegExpr.Create;
   RegExpr.Expression:='fcron\s+([0-9\.]+)';
   
   F:=TstringList.Create;
   F.LoadFromFile(t);
   for i:=0 to F.Count-1 do begin
       if RegExpr.Exec(F.Strings[i]) then begin
          result:=RegExpr.Match[1];
          break;
       end;
   end;
   logs.DeleteFile(t);
   RegExpr.free;
   F.Free;
   SYS.SET_CACHE_VERSION('APP_FCRON',result);
end;
//#########################################################################################
function tcron.ARTICA_VERSION():string;
var
   l:string;
   F:TstringList;

begin
   l:=artica_path + '/VERSION';
   if not FileExists(l) then exit('0.00');
   F:=TstringList.Create;
   F.LoadFromFile(l);
   result:=trim(F.Text);
   F.Free;
end;
//#############################################################################
  
  


end.
