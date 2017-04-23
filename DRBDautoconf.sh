#!/bin/bash -e

#
# Created by Suraj Nair
# Date - 22/04/2017
# Version: 1.0
#

#
#Check if we have privileges
#

if [ $(id -u) -ne 0 ]; then
	echo "Run this script as a Root user only" >&2
	exit 1
fi

#
# Getting IP from the system
#

IP=$(ip route get 8.8.8.8 | awk 'NR==1 {print $NF}')

LOGFILE=/root/installlog.txt 


#
#Check Error at any place and exit
#

checkerror()
{
RESULT=$1
if [ $RESULT != 0 ];then
echo "Errors occured while installing, Check $LOGFILE"
exit 127
fi
}


#
# Checking the IP with ipcalc
#
checkip()
{
ipcalc -cs $1 && return || echo "Invalid IP address syntax/range entered.. Quitting try running the script again" && exit 127
}

HOST1=
while [[ $HOST1 = "" ]]; do
   read -e -p "Enter the hostname of first node: " HOST1
done

FIRSTIP=
while [[ $FIRSTIP = "" ]]; do
   read -e -p "Please insert the IP for the node $HOST1: " FIRSTIP
done

checkip $FIRSTIP

HOST2=
while [[ $HOST2 = "" ]]; do
   read -e -p "Enter the hostname of second node: " HOST2
done

SECONDIP=
while [[ $SECONDIP = "" ]]; do
   read -e -p "Please insert the IP for the node $HOST2: " SECONDIP
done

checkip $SECONDIP


#
#Initializing Variables
#

TOTALDISKS=
COUNT=0
PORT=7789

ROOTDISK=`df -h | grep "/boot" | awk '{print $1}' | awk -F "/" '{print $3}' | sed -e 's/.$//'`

echo -e "The disk with the OS partitions involved is: $ROOTDISK 
Make sure you are not using $ROOTDISK in any of the further steps \n"

echo -e " The disks and size without the root partitions are: \n"

echo -e "=================="

echo -e "DISK:SIZE \n"

lsblk | grep -v "NAME" | grep -v $(df -h | grep "/boot" | awk '{print $1}' | awk -F "/" '{print $3}' | sed -e 's/.$//') | grep "disk" | awk '{print $1,":",$4}'

echo -e "==================\n"

echo -e "\n"

rm -rf /root/disks.txt || true >> $LOGFILE 2>&1

read -p "Do you wish to use all the above shown disk for drbd paritions?
Answer Y or N where:
'Y' means all these disk without the OS installations will be partitioned 100% for DRBD
'N' you can input the required disks in the next questions which will be partitioned 100% for DRBD
Please make your selection now:" SELECTION

if [ "$SELECTION" = "Y" ]
        then
                INTERDISKS=$(lsblk | grep -v "NAME" | grep -v $(df -h | grep "/boot" | awk '{print $1}' | awk -F "/" '{print $3}' | sed -e 's/.$//') | grep "disk" | awk '{print $1}' | tr '\n' ' ')
                for i in $INTERDISKS
                do
                        echo "/dev/${i}" >> /root/disks.txt
                done

                TOTALDISKS=`cat /root/disks.txt`
        else
                read -e -p "Make sure the names of the disks are the same on both $HOST1 and $HOST2 and you exclude $ROOTDISK from this list.
                Enter the absolute path for the disk to be formatted (ex. /dev/sdx) and used for drbd conf SEPERATED BY a SPACE: " TOTALDISKS
        fi


		
echo -e "The exact order of disks is important for DRBD configuration.
The order used here is 
$TOTALDISKS"

echo -e "Make sure you use this same sequence for the secondary node as well..."
		
sleep 5

#
# Installing DRBD 8.4
#

echo -e "Installing EPEL repo and Updating packages...\n"

rpm -Uvh http://www.elrepo.org/elrepo-release-6-6.el6.elrepo.noarch.rpm || true >> $LOGFILE 2>&1

yum update -y >> $LOGFILE 2>&1

checkerror $?

echo -e "Installing DRBD 8.4 and requried dependencies...\n"

yum -y install drbd84-utils kmod-drbd84 parted >> $LOGFILE 2>&1

checkerror $?

for DISKS in $TOTALDISKS;
do

echo -e "Going to partition $DISKS with 100% disk space..\n"

parted $DISKS --script mklabel gpt || true #Making labels as GPT for big partitions

parted $DISKS --script rm 1 || true >> $LOGFILE 2>&1

parted $DISKS --script rm 2 || true >> $LOGFILE 2>&1

parted $DISKS --script mkpart primary ext4 0% 100% # Using 100% Disk space for the partition

echo -e "Creating DRBD conf file for the device $DISKS: \n"

echo "resource drbd${COUNT} {
        protocol C;
        startup {
                wfc-timeout  0; # non-zero wfc-timeout can be dangerous (http://forum.proxmox.com/threads/3465-Is-it-safe-to-use-wfc-timeout-in-DRBD-configuration)
                degr-wfc-timeout 60;
#                become-primary-on both;
                become-primary-on $HOST1;
        }
        net {
                cram-hmac-alg sha1;
                shared-secret "abc666";
                allow-two-primaries;
                after-sb-0pri discard-zero-changes;
                after-sb-1pri discard-secondary;
                after-sb-2pri disconnect;
                max-buffers 8000;
                max-epoch-size 8000;
                sndbuf-size 0;
                #data-integrity-alg crc32c; # has to be enabled only for test and disabled for production use (check man drbd.conf, section "NOTES ON DATA INTEGRITY")
        }
        syncer {
                rate 900M;
                verify-alg md5;
                # rate after al-extents use-rle cpu-mask verify-alg csums-alg
        }
        on $HOST1 {
                device /dev/drbd${COUNT};
                disk ${DISKS}1;
                address $FIRSTIP:$PORT;
                meta-disk internal;
        }
        on $HOST2 {
                device /dev/drbd${COUNT};
                disk ${DISKS}1;
                address $SECONDIP:$PORT;
                meta-disk internal;
        }

}" > /etc/drbd.d/drbd${COUNT}.res

drbdadm create-md drbd${COUNT}

checkerror $?

let COUNT=COUNT+1
let PORT=PORT+1
done

echo -e "Installation and configuration of DRBD files and packages has been completed now..

You can check the /etc/drbd.d directory if the files intended for the given disks have been completed.

Make sure to use the following sequence only one by one seperated by spaces manually for the second node(In case this is your first node while installation):
$TOTALDISKS

Primary node for all the devices has been set to a default of $HOST1

Please change it as per your requirements.

Next manual steps:

1) Restart drbd service on both the $HOST1 and $HOST2 after confirming that this script was run and all the DRBD conf files are present according to your requirements.

2) Wiping the data of the secondary node from the primary node only with the following command:

drbdadm -- --overwrite-data-of-peer primary drbdx

where x is the number of drbd .res files found under /etc/drbd.d/ directory.

This should start the data sync

3) Make sure the Firewall rules are not blocking the ports as found in the drbd.resx files for connection.
"
