#!/bin/bash

# Taken from https://github.com/payperks/mongolvmbackup/
#
# Changed to run from bacula as ClientRunBeforeJob and ClientRunAfterJob
# Supposed that mongo LVM volume uses XFS filesystem (mount -o nouuid is used)

# ======================================================================
# Configuration options

MOUNTPOINT='/tmp/mongolvmsnap'

# Lock database before the snapshot is taken? It's not required if mongod
# uses journaling, but required if not journaling enabled or journals are
# located on separate volume then data files
lock_db_writes=no

# ======================================================================


print_help() {
  echo
  echo "$0: -g <lvmgroup> -v <lvmvolume> -a <start|stop>"
  echo
  echo "Snapshot MongoDB databases present on this host"
  echo "and mount it for later backup."
  echo
  exit 0
}


# Check for some required utilities
command lvcreate --help >/dev/null 2>&1 || { echo "Error: lvcreate is required.  Cannot continue."; exit 1; }
command lvremove --help >/dev/null 2>&1 || { echo "Error: lvremove is required.  Cannot continue."; exit 1; }



# Process CLI options
vgroup=''
volume=''
action=''

while [ $# -gt 0 ]
do
  case $1 in
    -h) print_help ;;
    --help) print_help ;;
    -a) action=$2 ; shift 2 ;;
    -g) vgroup=$2 ; shift 2 ;;
    -v) volume=$2 ; shift 2 ;;
    *) shift 1 ;;
  esac
done

# Check if action is valid
if [ "$action" != "start" -a "$action" != "stop" ]
then
  echo "Action (-a) must be either start or stop"
  exit 1
fi

# Check volume is really set
if [ "$vgroup" == "" ]
then
  echo "No group set, won't continue"
  exit 1
fi
if [ "$volume" == "" ]
then
  echo "No volume set, won't continue"
  exit 1
fi


# Check volume is a real LVM volume
if ! lvdisplay "/dev/$vgroup/$volume" >/dev/null 2>/dev/null
then
  echo "/dev/$vgroup/$volume is not a real LVM volume!"
  exit 1
fi

# Define the name of snapshot volume
snapvol="$volume-snap"

snap_start() {
  echo "==================== LVM MONGODB SNAPSHOT SCRIPT ====================="
  echo
  echo "  Snapshotting: /dev/${vgroup}/${volume}"
  echo
  
  # Create mount point
  if [ ! -d "$MOUNTPOINT" ]
  then
    echo "Creating mount point $MOUNTPOINT"
    mkdir -p "$MOUNTPOINT"
  fi
  
  # Unmount mountpoint if previos run was interrupted
  is_mounted=`mount | grep "$MOUNTPOINT" 2>&1 >/dev/null; echo $?`
  if [ $is_mounted -eq 0 ]
  then
    echo "Found that $MOUNTPOINT is already mounted, trying to unmount it..."
    umount -f $MOUNTPOINT
    if [ "$?" -ne 0 ]
    then
      echo "Cannot unmount $MOUNTPOINT, exiting..."
      exit 2
    fi
  fi
  
  # Create the snapshot
  if [ "$lock_db_writes" == "yes" ]
  then
    echo "Freezing MongoDB before LVM snapshot"
    mongo -eval "db.fsyncLock()"
    echo
  fi
  echo "Taking snapshot $snapvol"
  lvcreate --snapshot "/dev/$vgroup/$volume" --name "$snapvol" --extents '90%FREE'
    if [ "$?" -ne 0 ]
    then
      echo "Snapshot failed, exiting..."
      exit 3
    fi
  echo
  if [ "$lock_db_writes" == "yes" ]
  then
    echo "Snapshot OK; unfreezing DB"
    mongo -eval "db.fsyncUnlock()"
    echo
  fi
 
  # Mount the snapshot
  mount -v -o ro,nouuid "/dev/${vgroup}/${snapvol}" "${MOUNTPOINT}"
  if [ "$?" -ne 0 ]
  then
    echo "Mounting snapshot failed, exiting..."
    exit 4
  fi
  exit 0
}

snap_stop() {
  # Unmount & remove temp snapshot
  echo "Unmounting..."
  umount -fv "$MOUNTPOINT"
  if [ "$?" -ne 0 ]
  then
    echo "Unmounting snapshot failed, exiting..."
    exit 4
  fi
  echo
  echo "Removing temporary volume..."
  lvremove -f "/dev/${vgroup}/${snapvol}"
  if [ "$?" -ne 0 ]
  then
    echo "Removing snapshot failed, exiting..."
    exit 5
  fi
  exit 0
}

# ============================================================================
# do action
[ "$action" == "start" ] && snap_start;
[ "$action" == "stop" ] && snap_stop;


