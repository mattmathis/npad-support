#! /bin/bash

# initialize NPAD in an MLab slice
source /etc/mlab/slice-functions
source $SLICEHOME/conf/config.sh
source $SLICEHOME/.bash_profile
cd $SLICEHOME

set -e

echo Kill any prior servers
service httpd stop          || true
$SLICEHOME/init/stop.sh     || true
# Brutal workaround for buggy daemon scripts
killall /usr/bin/python     || true
killall /usr/sbin/tcpdump   || true

echo "Install httpd and perform System Update"
# echo "Check/Install system tools"
[ -f $SLICEHOME/.yumdone2 ] || \
    (
        rm -f $SLICEHOME/.yumdone*
        yum install -y httpd gnuplot-py gnuplot
        yum install -y paris-traceroute
        touch $SLICEHOME/.yumdone2
    )
# make sure that everything is up to date
yum update -y

# Enable/disable VSYS based on OS version
if [[ $( uname -r ) =~ 2.6.22.* ]] ; then
    echo "Removing /etc/web100_vsys.conf"
    rm -f /etc/web100_vsys.conf
elif [[ $( uname -r ) =~ 2.6.32.* ]] ; then
    echo "Creating /etc/web100_vsys.conf"
    echo "1" > /etc/web100_vsys.conf
else
    echo "Unknown kernel version: " `uname -r`
fi

if [ ! -f .side_samples_done ]; then
   mkdir -p $SLICEHOME/VAR/www/Sample
   (cd $SLICEHOME/VAR/www/Sample; mkSample.py)
   touch .side_samples_done
fi

# create directories as the user.
pushd $SLICEHOME/VAR

    mkdir -p logs run
    chown -R $SLICENAME:slices logs run

    echo "Capture our idenity and its various attributes"
    rm -f MYADDR MYFQDN MYLOCATION MYNODE LOCATION

    # Get and check our own IP ADDRESS
    MYADDR=$( get_slice_ipv4 ) 
    if [ -z "$MYADDR" ]; then
       echo "Failed to find my address: $MYADDR"
       exit 1
    fi
    echo $MYADDR > MYADDR

    # Be aware that $HOSTNAME is the ssh interface
    # MYFQDN and MYADDR are the service name and address
    MYFQDN="npad.iupui.$HOSTNAME"
    echo $MYFQDN > MYFQDN

    # XXXX should check that MYFQDN and MYADDR agree

    # Generate some nice names
    set `echo $HOSTNAME | tr '.' ' '`
    site=`echo $2 | tr -d '[0-9]' | tr '[a-z]' '[A-Z]'`
    location=`sed -n "s/^$site[ 	][ 	]*//p" $SLICEHOME/conf/Locations.txt`
    if [ -n "$location" -a "$3" = "measurement-lab" -a "$4" = "org" ] ; then
        MYLOCATION=$location
        MYNODE=$1.$2
    else
        MYLOCATION="(unknown near $site)"
        MYNODE=`basename $HOSTNAME .measurement-lab.org`
    fi
    echo $MYLOCATION > MYLOCATION
    echo $MYNODE > MYNODE
    echo "Configured node $MYNODE at $MYFQDN ($MYADDR) in $MYLOCATION"
popd

echo "Configure httpd"
# avoid redoing things
cp -f /etc/httpd/conf/httpd.conf $SLICEHOME/conf/httpd.conf.original
sed "s/MYFQDN/$MYFQDN/" $SLICEHOME/conf/httpd.conf.npad > /etc/httpd/conf/httpd.conf
sed "s;LOCATION;$MYLOCATION;" $SLICEHOME/conf/diag_form.html > $SLICEHOME/VAR/www/index.html
chkconfig httpd on
service httpd start

# NOTE: this is forcibly over-writing a pre-existing config within the slicebase.
sed -e "s;RSYNCDIR_SS;$RSYNCDIR_SS;" \
    -e "s;RSYNCDIR_NPAD;$RSYNCDIR_NPAD;" \
    -e "s;RSYNCDIR_PTR;$RSYNCDIR_PTR;" \
    $SLICEHOME/conf/rsyncd.conf.in > /etc/rsyncd.conf
    if [[ `hostname` == *"yyz01"* || `hostname` == *"yyc01"* || `hostname` == *"yul01"* ]]; then
       echo "    hosts allow = 108.170.192.0/18, 108.177.0.0/20, 142.250.0.0/15, 172.217.0.0/16, 172.253.0.0/16, 173.194.0.0/16, 192.178.0.0/15, 199.87.241.32/28, 207.223.160.0/20, 209.85.128.0/17, 216.239.32.0/19, 216.58.192.0/19, 64.233.160.0/19, 66.102.0.0/20, 66.249.64.0/19, 70.32.128.0/19, 70.90.219.48/29, 70.90.219.72/29, 72.14.192.0/18, 74.125.0.0/16, 23.228.128.64/26, 192.211.124.208/28" >> /etc/rsyncd.conf
    fi

mkdir -p $RSYNCDIR_SS
mkdir -p $RSYNCDIR_NPAD
mkdir -p $RSYNCDIR_PTR
chown -R $SLICENAME:slices /var/spool/$SLICENAME
# NOTE: Restart, since we just modified the config.
service rsyncd restart
