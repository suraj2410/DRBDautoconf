# DRBDautoconf
CentOS 6.x based DRBD auto install and configuration of files for underlying HDD's to use.

This script needs to be deployed on both the systems that you intend to use for DRBD purposes.

This has been only tested with CentOS 6.x version.

How to run:

1) Clone the repo
2) chmod 755 DRBDautoconf.sh
3) ./DRBDautoconf.sh
4) Provide the inputs for the script and note the disk order when shown.
   This same disk order needs to be provided as a manual input when running the script on the second node
5) At the end, follow some manual steps required to start the DRBD and sync it.

Suggestions and improvements are welcome :)
