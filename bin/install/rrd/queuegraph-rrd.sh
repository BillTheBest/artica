#!/bin/sh

# output the number of messages in the incoming, active, and deferred
# queues of postfix one per line suitable for use with snmpd/cricket/rrdtool
#
# 2003/01/24 Mike Saunders <method at method DOT cx>
#            mailqsize was originally written by Vivek Khera.  All I did was
#            make it update an rrd.
# 2003/04/14 Ralf Hildebrandt <ralf.hildebrandt at charite DOT de>
#            I bundled this with a modified mailgraph
# 2007/07/28 Ralf Hildebrandt <ralf.hildebrandt at charite DOT de>
#            find rrdtool using "which"

# change this to the location of rrdtool
RRDTOOL=/usr/bin/rrdtool

# change this to the location you want to store the rrd
RRDFILE=/opt/artica/var/rrd/queuegraph.rrd

if test ! -x $RRDTOOL ; then
	echo "ERROR: $RRDTOOL does not exist or is not executable"
	exit
fi

if test ! -f $RRDFILE ; then
	echo "Starting......: Creating RRD file $RRDFILE"

	$RRDTOOL create $RRDFILE --step 60 \
		DS:active:GAUGE:900:0:U \
		DS:deferred:GAUGE:900:0:U \
		RRA:AVERAGE:0.5:1:20160 \
		RRA:AVERAGE:0.5:30:2016 \
		RRA:AVERAGE:0.5:60:105120 \
		RRA:MAX:0.5:1:1440 \
		RRA:MAX:0.5:30:2016 \
		RRA:MAX:0.5:60:105120
fi

#set -x
qdir=`/usr/sbin/postconf -h queue_directory`
active=`find $qdir/incoming $qdir/active $qdir/maildrop -type f -print | wc -l | awk '{print $1}'`
deferred=`find $qdir/deferred -type f -print | wc -l | awk '{print $1}'`
#printf "active: %d\ndeferred: %d\n" $active $deferred

$RRDTOOL update $RRDFILE "N:$active:$deferred"
