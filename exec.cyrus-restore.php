<?php
include_once(dirname(__FILE__).'/ressources/class.templates.inc');
include_once(dirname(__FILE__).'/ressources/class.ini.inc');
include_once(dirname(__FILE__).'/ressources/class.ldap.inc');
include_once(dirname(__FILE__).'/ressources/class.cyrus.inc');
include_once(dirname(__FILE__).'/framework/class.unix.inc');
include_once(dirname(__FILE__) . '/ressources/class.os.system.inc');
include_once(dirname(__FILE__)."/framework/frame.class.inc");

if(posix_getuid()<>0){die("Cannot be used in web server mode\n\n");}
include_once(dirname(__FILE__).'/framework/class.unix.inc');

if($$argv[1]="--create-mbx"){
	createMbx($argv[2]);
	die();
}

if($argv[1]=="--move-default-current"){
	move_default_dir_to_currentdir();
	die();
}

if($argv[1]=="--rebuildmailboxes"){
	rebuild_all_mailboxes($argv[2]);
	die();
}

if(!Build_pid_func(__FILE__,"MAIN")){
	writelogs(basename(__FILE__).":Already executed.. aborting the process",basename(__FILE__),__FILE__,__LINE__);
	die();
}

if($argv[1]=="--move-new-dir"){
	move_default_dir_to_newdir($argv[2]);
}

if($argv[1]=='ldap'){
	$_GET["LDAP_RESTORE_ONLY"]=true;
	$_GET["PATH_RESTORE"]=$argv[2];
	ldap_restore();
	die();
}
if($argv[1]=='mysql'){
	$_GET["PATH_RESTORE"]=$argv[2];
	MysqlRestore();
	die();
}

$_GET["PATH_RESTORE"]=$argv[1];
if(!is_dir($_GET["PATH_RESTORE"])){
	events("unable to stat {$_GET["PATH_RESTORE"]}");
	die();
}


cyrus_restore();
ArticaSettingsrestore();
ldap_restore();
MysqlRestore();
RefreshServices();




function events($text){
		$f=new debuglogs();
		$pf=md5($_GET["PATH_RESTORE"]);
		echo $text ."\n";
		$f->events(basename(__FILE__)." $text","/var/log/artica-postfix/artica-restore-$pf.debug");
		}
		
function cyrus_restore(){
	$unix=new unix();
	$tmp=$unix->FILE_TEMP();
	events("restore cyrus-imap mailboxes operations");
	events("restore cyrus-imap mailboxes please wait few minutes");
	shell_exec("/usr/share/artica-postfix/bin/artica-backup --restore-cyrus-single-backup \"{$_GET["PATH_RESTORE"]}\" --verbose >$tmp 2>&1");
	events(@file_get_contents($tmp));
	@unlink($tmp);
	events("restore cyrus-imap mailboxes done...");
}

function MysqlRestore(){
	$unix=new unix();
	$tmp=$unix->FILE_TEMP();
	events("restore Mysql databases operations");
	events("restore Mysql databases please wait few minutes");
	$size=$unix->DIRSIZE_KO("{$_GET["PATH_RESTORE"]}/mysql_backup");
	events("restore Mysql databases size=$size Ko");
	if($size==0){
		events("restore Mysql Databases failed, directory {$_GET["PATH_RESTORE"]}/mysql_backup is empty...");
		return null;
	}
	shell_exec("/usr/share/artica-postfix/bin/artica-backup --restore-cyrus-mysql \"{$_GET["PATH_RESTORE"]}/mysql_backup\" --verbose >$tmp 2>&1");
	events(@file_get_contents($tmp));
	@unlink($tmp);
	events("restore Mysql Databases done...");	
	
}


function ArticaSettingsrestore(){
	$unix=new unix();
	$tmp=$unix->FILE_TEMP();
	events("restore Artica settings operations");
	events("restore Artica settings operations");
	$size=$unix->DIRSIZE_KO("{$_GET["PATH_RESTORE"]}/etc-artica-postfix");
	events("restore Artica settingssize=$size Ko");
	if($size==0){
		events("restore Artica settings failed, directory {$_GET["PATH_RESTORE"]}/etc-artica-postfix...");
		return null;
	}
	shell_exec("/bin/cp -rf {$_GET["PATH_RESTORE"]}/etc-artica-postfix/artica-postfix/* /etc/artica-postfix/");
	shell_exec("/usr/share/artica-postfix/bin/process1 --force ". md5(date('Y-m-d H:i:s')));
	
	@unlink("/etc/artica-postfix/FROM_ISO");
	@unlink("/etc/artica-postfix/artica-postfix.pid");
	@unlink("/etc/artica-postfix/mon.pid");
	shell_exec("/etc/init.d/artica-postfix restart daemon");
	@unlink("/etc/artica-postfix/settings/Daemons/SystemCpuNumber");
	
	events("restore Artica settings done...");		
}

function RefreshServices(){
	$unix=new unix();
	events("recompile parameters...");
	events("recompile parameters... please wait few minutes");
	$cmd=$unix->LOCATE_PHP5_BIN().' '. dirname(__FILE__).'/exec.services.change.ldap.php';
	exec($cmd);
	shell_exec("/etc/init.d/artica-postfix restart daemon");
	shell_exec("/etc/init.d/artica-postfix restart apache");
	shell_exec('/usr/share/artica-postfix/bin/artica-install --cyrus-checkconfig --force');
	shell_exec('/etc/init.d/artica-postfix restart imap &');	
	
	
}




function ldap_restore(){
	$unix=new unix();
	$tmp=$unix->FILE_TEMP();	
	if($_GET["LDAP_RESTORE_ONLY"]){ArticaSettingsrestore();}
	events("Restoring LDAP database...");
	events("restoring LDAP database please wait few minutes");
	$ldif="{$_GET["PATH_RESTORE"]}/ldap_backup/ldap.ldif";
	if(!is_file($ldif)){
		events("Restoring LDAP database unable to stat $ldif");
		return null;
	}
	shell_exec("/usr/share/artica-postfix/bin/artica-backup --instant-ldap-recover $ldif --verbose >$tmp 2>&1");
	events(@file_get_contents($tmp));
	@unlink($tmp);
	events("restore LDAP Database done...");	
	
}

function move_default_dir_to_currentdir(){
	$unix=new unix();
	$logs="/usr/share/artica-postfix/ressources/logs/cyrus_dir_logs";
	$currentdir=$unix->IMAPD_GET("partition-default");
	if(!is_dir($currentdir)){return;}
	system($unix->find_program("mv")." -fv /var/spool/cyrus/mail/* $currentdir/ >$logs 2>&1");
	system("/etc/init.d/artica-postfix restart imap >>$logs 2>&1");
	@chmod("/usr/share/artica-postfix/ressources/logs/cyrus_dir_logs",0755);
	
}

function move_default_dir_to_newdir($path){
	$path=base64_decode($path);
	if($path==null){return null;}
	if(!is_dir($path)){return null;}
	$unix=new unix();
	$logs="/usr/share/artica-postfix/ressources/logs/cyrus_dir_logs";
	$currentdir=$unix->IMAPD_GET("partition-default");
	$sock=new sockets();
	$sock->SET_INFO("CyrusPartitionDefault",$path);
	system($unix->find_program("mv")." -fv $currentdir/* $path/ >$logs 2>&1");
	system("/usr/share/artica-postfix/bin/artica-install --reconfigure-cyrus >>$logs 2>&1");
	@chmod("/usr/share/artica-postfix/ressources/logs/cyrus_dir_logs",0755);
	
}

function createMbx($uid){
	$cyrus=new cyrus();
	$unix=new unix();
	$sudo=$unix->find_program("sudo");
	$reconstruct=$unix->LOCATE_CYRRECONSTRUCT();
	$cyrus->CreateMailbox($uid);
	shell_exec("$sudo -u cyrus $reconstruct -f -r user/$uid >/dev/null 2>&1");
}

function rebuild_all_mailboxes($ou_encoded){
	if(!Build_pid_func(__FILE__,"rebuild_all_mailboxes_{$ou_encoded}")){
		rebuild_all_mailboxes_events("Already executed",$ou_encoded);
		return;
	}
	$ldap=new clladp();
	$filter="(&(objectClass=userAccount)(|(cn=*)(mail=*)))";
	$attrs=array("displayName","uid","mail","givenname","telephoneNumber","title","sn","mozillaSecondEmail","employeeNumber");
	$dn="ou=". base64_decode($ou_encoded).",dc=organizations,$ldap->suffix";
	$hash=$ldap->Ldap_search($dn,$filter,$attrs);
	$number=$hash["count"];
	rebuild_all_mailboxes_events("$number user(s) in $dn",$ou_encoded);

	for($i=0;$i<$number;$i++){
		$userARR=$hash[$i];
		$uid=$userARR["uid"][0];
		$ct=new user($uid);
		
		if(strpos($uid,'$')>0){
			rebuild_all_mailboxes_events("$ct->DisplayName SKIP {computer}=TRUE",$ou_encoded);
			continue;
		}
		
		if($ct->MailboxActive<>'TRUE'){
			rebuild_all_mailboxes_events("$ct->DisplayName SKIP MailboxActive=FALSE",$ou_encoded);
			continue;
		}
		$cyrus=new cyrus();
		if($cyrus->MailBoxExists($uid)){
			rebuild_all_mailboxes_events("[$number/$i]:: $uid: {mailbox_already_exists}",$ou_encoded);
			continue;
		}
			
		$cyrus->CreateMailbox($uid);
		rebuild_all_mailboxes_events("[$number/$i]::$uid: $cyrus->cyrus_infos",$ou_encoded);
	}
	
	rebuild_all_mailboxes_events("{success}",$ou_encoded);
	
}
function rebuild_all_mailboxes_events($text,$ou_encoded){
	echo $text ."\n";
		$file="/usr/share/artica-postfix/ressources/logs/web/".md5($ou_encoded)."-mailboxes-rebuilded.log";
		$pid=getmypid();
		$date=date("H:i:s");
		$f =@fopen($file, 'a');
		$line="$date [$pid] $text\n";
		@fwrite($f,$line);
		@fclose($f);	
		@chmod($file,0777);
	writelogs("$text","rebuild_all_mailboxes",__FILE__,__LINE__);
	
}
		


?>