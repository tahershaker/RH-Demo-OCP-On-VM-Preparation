#!/usr/bin/env bash

#===================================================================================

#-------------------------------------------------------------
# Add strict bash safety & Set trap to handel script interruption
#-------------------------------------------------------------

set -Eeuo pipefail
trap 'echo "\n ---- Script interrupted. Exiting..."; exit 1' INT TERM
trap 'rc=$?; echo "\n ---- ERROR: line ${LINENO}: ${BASH_COMMAND}" >&2; exit $rc' ERR

#===================================================================================

#-------------------------------------------------------------
# Script Description
#-------------------------------------------------------------

################################################################################
# This script prepares the bastion host in a VMware-based lab environment for
# deploying an OpenShift cluster using the Assisted Installer.
#
# It installs the required tooling and automates common, repeatable preparation
# tasks such as interacting with vCenter, managing datastores, and provisioning
# virtual machines. No DNS or load balancer configuration is performed on the
# bastion host, as these services are provided externally by the lab platform.
#
# This script is intended for Option 1 (Assisted Installer) deployments.
################################################################################

#===================================================================================

#-------------------------------------------------------------
# Set Colors For Outputs
#-------------------------------------------------------------

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
GREY='\033[0;90m'
BLUE='\033[0;34m'
BRIGHT_BLUE='\033[1;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'   # Reset / No Color

#===================================================================================

#-------------------------------------------------------------
# Reset variables (script + GOVC env) for safe re-runs
#-------------------------------------------------------------

# Unset GOVC environment variables (avoid stale sessions)
unset GOVC_URL GOVC_USERNAME GOVC_PASSWORD GOVC_INSECURE GOVC_DATACENTER

# Unset script variables (avoid stale values if sourced or reused)
unset VCENTER_URL VCENTER_USERNAME VCENTER_PASSWORD OCP_RELEASE LAB_DOMAIN LAB_ID
unset CLUSTER_MODE CLUSTER_TYPE MASTER_COUNT WORKER_COUNT
unset MASTER_CPU MASTER_RAM_GB MASTER_DISK_GB WORKER_CPU WORKER_RAM_GB WORKER_DISK_GB
unset ISO_WGET_CMD ISO_URL ISO_DIR ISO_FILENAME ISO_FULL_PATH
unset TMP_DIR OC_TAR OC_URL
unset DC_NAME GOVC_DATACENTER_PATH
unset GOVC_VM_FOLDER_PATH GOVC_VM_FOLDER_NAME
unset GOVC_DATASTORE_PATH GOVC_DATASTORE_NAME
unset GOVC_NETWORK_PATH GOVC_NETWORK_NAME
unset DATASTORE_ISO_PATH
unset VM_LIST VM_NAME

#===================================================================================

#-------------------------------------------------------------
# Create Functions To Be Used In Script
#-------------------------------------------------------------

# Function to Read Non-Empty Input (Rejects empty or whitespace-only)
read_non_empty() {
  local prompt="$1"
  local value

  while true; do
    read -rp "$prompt" value
    value="$(echo "$value" | xargs)"

    if [[ -z "$value" ]]; then
      echo -e "${RED}   Input cannot be empty. Please try again.${NC}" >&2
      echo ""
      continue
    fi

    echo "$value"
    return 0
  done
}

#------------------------------------------------------------------------------

# Function to Validate integer input (non-empty, numeric, within range)
read_int_in_range() {
  local prompt="$1" min="$2" max="$3" value

  while true; do
    read -rp "$prompt" value

    if [[ -z "$value" ]] || ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt "$min" ]] || [[ "$value" -gt "$max" ]]; then
      echo -e "${RED}   Invalid input. Enter a numeric value between $min and $max.${NC}" >&2
      continue
    fi

    echo "$value"
    return 0
  done
}

#------------------------------------------------------------------------------

# Function to Confirm user input Y/N
confirm_yn() {
  local prompt="$1" ans
  while true; do
    read -rp "$prompt" ans
    case "$ans" in
      [Yy]) return 0 ;;
      [Nn]) return 1 ;;
      *) echo -e "${RED}   Invalid input. Please enter Y or N only.${NC}" >&2 ;;
    esac
  done
}

#------------------------------------------------------------------------------

# Function to create the required VMs
create_vm() {
  local vm_name="$1"
  local cpu="$2"
  local ram_gb="$3"
  local disk_gb="$4"
  local vm_number="$5"
  local vm_type="$6"     # Master | Worker

  local os_disk_gb=120

  # Decide disk layout 
  # two_disks=true for: compact OR (standard AND worker)
  local two_disks="false"
  if [[ "$CLUSTER_MODE" == "compact" ]]; then
    two_disks="true"
  elif [[ "$CLUSTER_MODE" == "standard" && "$vm_type" == "Worker" ]]; then
    two_disks="true"
  fi

  echo -e "${CYAN}   Creating VM number ${vm_number}: ${vm_name}${NC}"

  # Create VM (govc vm.create may power it on automatically)
  if ! govc vm.create -folder "$GOVC_VM_FOLDER_PATH" -ds "$GOVC_DATASTORE_PATH" -net "$GOVC_NETWORK_PATH" \
      -c "$cpu" -m "$((ram_gb * 1024))" -disk "${os_disk_gb}G" \
      "$vm_name" >/dev/null 2>&1; then
    echo -e "${RED}   ERROR: Failed to create VM: ${vm_name}${NC}"
    echo -e "${RED}   An unexpected error. Please check issue and try again.${NC}"
    exit 1
  fi

  # Ensure powered off before configuration
  govc vm.power -off -force "$vm_name" >/dev/null 2>&1 || true    

  # Print VM created
  echo "   VM number ${vm_number} - ${vm_name} - created successfully. Adding required config..."

  # sleep for 3 seconds to ensure VM is powered-off
  sleep 3

  # Add second disk for worker nodes in standard cluster type or all nodes in a compact cluster type
  if [[ "$two_disks" == "true" ]]; then
    echo "   ---> Adding second (data) disk with the size of ${disk_gb}G ..."
    if ! govc vm.disk.create -vm "$vm_name" -ds "$GOVC_DATASTORE_PATH" -name "${vm_name}-data.vmdk" -size "${disk_gb}G" >/dev/null 2>&1; then
      echo -e "${RED}   ERROR: Failed to add data disk (${disk_gb}G) to ${vm_name}${NC}"
      echo -e "${RED}   An unexpected error. Please check issue and try again.${NC}"
      exit 1
    fi
  fi

  # Enable disk UUID
  echo "   Setting disk.EnableUUID to TRUE..."
  if ! govc vm.change -vm "$vm_name" -e="disk.EnableUUID=TRUE" >/dev/null 2>&1; then
    echo -e "${RED}   ERROR: Failed to set disk.EnableUUID=TRUE on ${vm_name}${NC}"
    echo -e "${RED}   An unexpected error. Please check issue and try again.${NC}"
    exit 1
  fi

  # Add CDROM
  echo "   Adding CD-ROM to VM..."
  if ! govc device.cdrom.add -vm "$vm_name" >/dev/null 2>&1; then
    echo -e "${RED}   ERROR: Failed to add CDROM on ${vm_name}${NC}"
    echo -e "${RED}   An unexpected error. Please check issue and try again.${NC}"
    exit 1
  fi

  # Insert ISO
  echo "   Inserting ISO to VM..."
  if ! govc device.cdrom.insert -vm "$vm_name" -ds "$GOVC_DATASTORE_NAME" "$DATASTORE_ISO_PATH" >/dev/null 2>&1; then
    echo -e "${RED}   ERROR: Failed to insert ISO on ${vm_name}${NC}"
    echo -e "${RED}   An unexpected error. Please check issue and try again.${NC}"
    exit 1
  fi

  # Enable connect-at-boot (your confirmed working command)
  echo "   Enabling CD-ROM to Connect-At-Boot on VM..."
  local cdrom_dev
  cdrom_dev="$(govc device.ls -vm "$vm_name" | awk '/^cdrom-/ {print $1; exit}')"
  if [[ -z "$cdrom_dev" ]]; then
    echo -e "${RED}   ERROR: Could not detect CDROM device for ${vm_name}${NC}"
    echo -e "${RED}   An unexpected error. Please check issue and try again.${NC}"
    exit 1
  fi

  if ! govc device.connect -vm "$vm_name" "$cdrom_dev" >/dev/null 2>&1; then
    echo -e "${RED}   ERROR: Failed to enable CDROM connect-at-boot on ${vm_name}${NC}"
    echo -e "${RED}   An unexpected error. Please check issue and try again.${NC}"
    exit 1
  fi
  
  # Print VM configured
  echo "   VM number ${vm_number} - ${vm_name} - configured successfully. Powering On..."

  # Sleep for 3 sec and then power-on VM.
  sleep 3
  if ! govc vm.power -on "$vm_name" >/dev/null 2>&1; then
    echo -e "${RED}   ERROR: Failed to power on ${vm_name}${NC}"
    echo -e "${RED}   An unexpected error. Please check issue and try again.${NC}"
    exit 1
  fi

  echo -e "${GREEN}   VM number ${vm_number} - ${vm_name} - created & configured successfully. Proceeding...${NC}"
}

#===================================================================================

#-------------------------------------------------------------
# Print Staring Script Message
#-------------------------------------------------------------

echo -e "${RED}"
echo "  --------------------------------------------------------------------------------  "
echo " | ================       Dedicated DNS Records Environment       =============== | "
echo " | ------------------------------------------------------------------------------ | "
echo " |                                                                                | "
echo " |  █████╗  ███████╗ ███████╗ ██╗ ███████╗ ████████╗ ███████╗ ██████╗             | "
echo " | ██╔══██╗ ██╔════╝ ██╔════╝ ██║ ██╔════╝ ╚══██╔══╝ ██╔════╝ ██╔══██╗            | "
echo " | ███████║ ███████╗ ███████╗ ██║ ███████╗    ██║    █████╗   ██║  ██║            | "
echo " | ██╔══██║ ╚════██║ ╚════██║ ██║ ╚════██║    ██║    ██╔══╝   ██║  ██║            | "
echo " | ██║  ██║ ███████║ ███████║ ██║ ███████║    ██║    ███████╗ ██████╔╝            | "
echo " | ╚═╝  ╚═╝ ╚══════╝ ╚══════╝ ╚═╝ ╚══════╝    ╚═╝    ╚══════╝ ╚═════╝             | "
echo " | ██╗ ███╗   ██╗ ███████╗ ████████╗  █████╗  ██╗      ██╗                        | "
echo " | ██║ ████╗  ██║ ██╔════╝ ╚══██╔══╝ ██╔══██╗ ██║      ██║                        | "
echo " | ██║ ██╔██╗ ██║ ███████╗    ██║    ███████║ ██║      ██║                        | "
echo " | ██║ ██║╚██╗██║ ╚════██║    ██║    ██╔══██║ ██║      ██║                        | "
echo " | ██║ ██║ ╚████║ ███████║    ██║    ██║  ██║ ███████╗ ███████╗                   | "
echo " | ╚═╝ ╚═╝  ╚═══╝ ╚══════╝    ╚═╝    ╚═╝  ╚═╝ ╚══════╝ ╚══════╝                   | "
echo " | ██████╗  ██████╗  ███████╗ ██████╗                                             | "
echo " | ██╔══██╗ ██╔══██╗ ██╔════╝ ██╔══██╗                                            | "
echo " | ██████╔╝ ██████╔╝ █████╗   ██████╔╝                                            | "
echo " | ██╔═══╝  ██╔══██╗ ██╔══╝   ██╔═══╝                                             | "
echo " | ██║      ██║  ██║ ███████╗ ██║                                                 | "
echo " | ╚═╝      ╚═╝  ╚═╝ ╚══════╝ ╚═╝                                                 | "
echo "  --------------------------------------------------------------------------------  "
echo ""
echo " --- Starting the Assisted Installer Preparation automation script For Dedicated DNS Enviroenemtn..."
echo -e "${NC}"

echo " ================================================================================== "
echo ""

#===================================================================================

#-------------------------------------------------------------
# Collect and Confirm User Inputs For Lab Environment Info
#-------------------------------------------------------------

echo -e "${YELLOW} Collect & Confirm Lab Environment Info${NC}"
echo -e "${YELLOW} ---------------------------------------${NC}"
echo ""

while true; do
  echo -e "${YELLOW} - Please provide the required lab Environment info below:${NC}"
  echo -e "${CYAN}     - VMware vCenter Server Info:${NC}"
  VCENTER_URL=$(read_non_empty "       Enter vCenter URL (e.g. vc.example.com): ")
  VCENTER_USERNAME=$(read_non_empty "       Enter vCenter username: ")
  VCENTER_PASSWORD=$(read_non_empty "       Enter vCenter password: ")
  GOVC_VM_FOLDER_PATH=$(read_non_empty "       Enter VM folder full path (e.g. /SDDC-Datacenter/vm/Workloads/sandbox-r5vnx): ")
  GOVC_DATASTORE_NAME=$(read_non_empty "       Enter datastore name only (e.g. workload_share_yBaQN): ")
  GOVC_NETWORK_NAME=$(read_non_empty "       Enter network name only (e.g. segment-sandbox-r5vnx): ")
  echo ""

  echo -e "${CYAN}     - Red Hat OpenShift Cluster Info:${NC}"
  OCP_RELEASE=$(read_non_empty "       Enter OpenShift release (e.g. 4.20.4): ")
  echo ""

  # Extract datacenter name, datastore + network paths from the VM folder path
  DC_NAME="$(echo "$GOVC_VM_FOLDER_PATH" | awk -F'/' '{print $2}')"
  GOVC_DATACENTER_PATH="/${DC_NAME}"
  GOVC_VM_FOLDER_NAME="$(echo "$GOVC_VM_FOLDER_PATH" | awk -F'/' '{print $5}')"
  GOVC_VM_FOLDER_NAME="/Workloads/${GOVC_VM_FOLDER_NAME}"
  GOVC_DATASTORE_PATH="${GOVC_DATACENTER_PATH}/datastore/${GOVC_DATASTORE_NAME}"
  GOVC_NETWORK_PATH="${GOVC_DATACENTER_PATH}/network/${GOVC_NETWORK_NAME}"

  echo -e "${YELLOW} - Please review the provided information below & confirm (Y/N):${NC}"
  echo "   ----------------------------------------"
  echo "   vCenter URL       : $VCENTER_URL"
  echo "   vCenter Username  : $VCENTER_USERNAME"
  echo "   vCenter Password  : $VCENTER_PASSWORD"
  echo "   Datacenter Name   : $DC_NAME"
  echo "   Datacenter Path   : $GOVC_DATACENTER_PATH"
  echo "   VM Folder Name    : $GOVC_VM_FOLDER_NAME"
  echo "   VM Folder Path    : $GOVC_VM_FOLDER_PATH"
  echo "   Datastore Name    : $GOVC_DATASTORE_NAME"
  echo "   Datastore Path    : $GOVC_DATASTORE_PATH"
  echo "   Network Name      : $GOVC_NETWORK_NAME"
  echo "   Network Path      : $GOVC_NETWORK_PATH"
  echo "   OpenShift Release : $OCP_RELEASE"
  echo "   ----------------------------------------"
  echo ""

  if confirm_yn "   Are the above provided information correct? (Y/N): "; then
    echo -e "${GREEN}   Input confirmed. Proceeding...${NC}"
    break
  else
    echo -e "${YELLOW}   Re-entering input details...${NC}"
    echo ""
  fi
done

# Export govc environment variables
export GOVC_URL="$VCENTER_URL"
export GOVC_USERNAME="$VCENTER_USERNAME"
export GOVC_PASSWORD="$VCENTER_PASSWORD"
export GOVC_DATACENTER="$DC_NAME"
export GOVC_INSECURE=1

#----------------------------------------------------------------------------------
# Section Environment Outputs
#
# This section captures the required lab and vCenter details and exports them as
# environment variables for use by govc and OpenShift preparation tasks.
#
# Variables set by this section:
# - GOVC_URL        : vCenter URL
# - GOVC_USERNAME   : vCenter username
# - GOVC_PASSWORD   : vCenter password
# - GOVC_INSECURE   : Disable TLS certificate verification (lab environments)
# - OCP_RELEASE     : OpenShift release version
#----------------------------------------------------------------------------------

#Print Separator
echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#----------------------------------------------------------------------------------
# Check The Required OCP Cluster Type & Confirm
#----------------------------------------------------------------------------------

echo -e "${YELLOW} Check The Required OCP Cluster Type${NC}"
echo -e "${YELLOW} -----------------------------------${NC}"
echo ""

while true; do
  echo ""
  echo -e "${YELLOW} - Please Select The Intended OpenShift Cluster Type:${NC}"
  echo "   1) 3-node compact cluster (masters also act as workers)"
  echo "   2) Standard cluster (3 masters + x worker nodes)"

  # --- Ask for cluster type ---
  while true; do
    read -rp "   Enter your choice (1 or 2): " CLUSTER_TYPE
    [[ "$CLUSTER_TYPE" =~ ^[12]$ ]] && break
    echo -e "${RED}   Invalid choice. Please enter 1 or 2.${NC}"
  done

  # --- Set variables based on choice ---
  if [[ "$CLUSTER_TYPE" == "1" ]]; then
    echo -e "${GREEN}      Selected: 3-node compact cluster${NC}"
    CLUSTER_MODE="compact"
    MASTER_COUNT=3
    WORKER_COUNT=0
  else
    echo -e "${GREEN}      Selected: Standard cluster${NC}"
    CLUSTER_MODE="standard"
    MASTER_COUNT=3

    while true; do
      read -rp "      Enter number of worker nodes [1–5] (default: 3): " WORKER_COUNT
      WORKER_COUNT=${WORKER_COUNT:-3}

      if [[ "$WORKER_COUNT" =~ ^[0-9]+$ ]] && [[ "$WORKER_COUNT" -ge 1 ]] && [[ "$WORKER_COUNT" -le 5 ]]; then
        break
      fi
      echo -e "${RED}      Invalid input. Please enter a number between 1 and 5.${NC}"
    done
  fi

  # --- Print summary + confirm ---
  echo ""
  echo -e "${YELLOW} - Please confirm the cluster selection:${NC}"
  echo "   ----------------------------------------"
  echo "   Cluster Mode   : $CLUSTER_MODE"
  echo "   Master Nodes   : $MASTER_COUNT"
  echo "   Worker Nodes   : $WORKER_COUNT"
  echo "   ----------------------------------------"
  echo ""

  if confirm_yn "   Is this correct? (Y/N): "; then
    echo -e "${GREEN}   Cluster selection confirmed. Proceeding...${NC}"
    break
  else
    echo -e "${YELLOW}   Re-entering cluster selection...${NC}"
  fi
done

#----------------------------------------------------------------------------------
# Section Environment Outputs
#
# This section defines the OpenShift cluster deployment model and node topology
# based on user selection.
#
# Variables set by this section:
# - CLUSTER_MODE    : Cluster deployment mode (compact | standard)
# - MASTER_COUNT    : Number of control plane nodes
# - WORKER_COUNT    : Number of worker nodes
#----------------------------------------------------------------------------------

#Print Separator
echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#----------------------------------------------------------------------------------
# Check VM Sizing Configuration (Defaults + Optional Custom + Confirmation)
#----------------------------------------------------------------------------------

echo -e "${YELLOW} Check The Required Node(s) HW Resources${NC}"
echo -e "${YELLOW} ---------------------------------------${NC}"
echo ""

# ----------------------------
# Check if COMPACT CLUSTER - then provide the defaults and ask for confirmation or Retrieve user required inputs
# ----------------------------
if [[ "$CLUSTER_MODE" == "compact" ]]; then
  # Defaults
  MASTER_CPU=12; MASTER_RAM_GB=32; MASTER_DISK_GB=250

  # Thresholds
  CPU_MIN=12; CPU_MAX=16; RAM_MIN=24; RAM_MAX=48; DISK_MIN=120; DISK_MAX=250

  echo -e "${YELLOW} - Selected OpenShift Cluster Type is 3-node Compact Cluster.${NC}"
  echo -e "${YELLOW} - Below are the default node HW resources:${NC}"
  echo "   ---------------------------"
  echo "   vCPU   : $MASTER_CPU"
  echo "   RAM    : $MASTER_RAM_GB GB"
  echo "   Disk   : $MASTER_DISK_GB GB"
  echo "   ---------------------------"
  echo ""

  if confirm_yn "   Proceed with these default values (Y/N)?"; then
    echo -e "${GREEN}   Using default VM sizing. Proceeding...${NC}"
  else
    while true; do
      echo -e "${CYAN}   Enter custom VM sizing for compact nodes:${NC}"

      MASTER_CPU=$(read_int_in_range "   vCPU [${CPU_MIN}-${CPU_MAX}]: " "$CPU_MIN" "$CPU_MAX")
      MASTER_RAM_GB=$(read_int_in_range "   RAM in GB [${RAM_MIN}-${RAM_MAX}]: " "$RAM_MIN" "$RAM_MAX")
      MASTER_DISK_GB=$(read_int_in_range "   Disk in GB [${DISK_MIN}-${DISK_MAX}]: " "$DISK_MIN" "$DISK_MAX")

      echo ""
      echo -e "${YELLOW}   Please confirm the custom VM sizing:${NC}"
      echo "   ------------------------------"
      echo "   vCPU  : $MASTER_CPU"
      echo "   RAM   : ${MASTER_RAM_GB} GB"
      echo "   Disk  : ${MASTER_DISK_GB} GB"
      echo "   ------------------------------"
      echo ""

      if confirm_yn "   Proceed with this VM sizing (Y/N)?"; then
        echo -e "${GREEN}   Custom VM sizing confirmed. Proceeding...${NC}"
        break
      fi

      echo -e "${YELLOW}   Re-entering custom VM sizing...${NC}"
    done
  fi

  # In compact mode, masters act as workers
  WORKER_CPU=0
  WORKER_RAM_GB=0
  WORKER_DISK_GB=0

# ----------------------------
# Check if STANDARD CLUSTER - then provide the defaults and ask for confirmation or Retrieve user required inputs
# ----------------------------
else
  # Defaults
  MASTER_CPU=4; MASTER_RAM_GB=16; MASTER_DISK_GB=120
  WORKER_CPU=8; WORKER_RAM_GB=32; WORKER_DISK_GB=200

  # Thresholds - masters
  M_CPU_MIN=4;  M_CPU_MAX=8; M_RAM_MIN=12; M_RAM_MAX=24; M_DISK_MIN=120; M_DISK_MAX=200

  # Thresholds - workers
  W_CPU_MIN=8;  W_CPU_MAX=16; W_RAM_MIN=16; W_RAM_MAX=48; W_DISK_MIN=120; W_DISK_MAX=250

  echo -e "${YELLOW} - Selected OpenShift Cluster Type is Standard Cluster (3 Master + $WORKER_COUNT Worker).${NC}"
  echo -e "${YELLOW} - Below are the default node HW resources:${NC}"
  echo "   -----------------------------------"
  echo "   Master vCPU   : $MASTER_CPU"
  echo "   Master RAM    : $MASTER_RAM_GB GB"
  echo "   Master Disk   : $MASTER_DISK_GB GB"
  echo "   Worker vCPU   : $WORKER_CPU"
  echo "   Worker RAM    : $WORKER_RAM_GB GB"
  echo "   Worker Disk   : $WORKER_DISK_GB GB"
  echo "   -----------------------------------"
  echo ""


  if confirm_yn "   Proceed with these default values (Y/N)?"; then
    echo -e "${GREEN}   Using default VM sizing. Proceeding...${NC}"
  else
    # --- Custom sizing for masters (with confirmation) ---
    while true; do
      echo -e "${CYAN}   Enter custom VM sizing for Master nodes:${NC}"

      MASTER_CPU=$(read_int_in_range "   Master vCPU [${M_CPU_MIN}-${M_CPU_MAX}]: " "$M_CPU_MIN" "$M_CPU_MAX")
      MASTER_RAM_GB=$(read_int_in_range "   Master RAM in GB [${M_RAM_MIN}-${M_RAM_MAX}]: " "$M_RAM_MIN" "$M_RAM_MAX")
      MASTER_DISK_GB=$(read_int_in_range "   Master Disk in GB [${M_DISK_MIN}-${M_DISK_MAX}]: " "$M_DISK_MIN" "$M_DISK_MAX")

      echo ""
      echo -e "${YELLOW}   Please confirm the master VM sizing:${NC}"
      echo "   ----------------------------------------"
      echo "   vCPU  : $MASTER_CPU"
      echo "   RAM   : ${MASTER_RAM_GB} GB"
      echo "   Disk  : ${MASTER_DISK_GB} GB"
      echo "   ----------------------------------------"
      echo ""

      if confirm_yn "   Proceed with this master sizing (Y/N)?"; then
        echo -e "${GREEN}   Master VM sizing confirmed. Proceeding...${NC}"
        break
      fi

      echo -e "${YELLOW}   Re-entering master VM sizing...${NC}"
    done

    echo ""

    # --- Custom sizing for workers (with confirmation) ---
    while true; do
      echo -e "${CYAN}   Enter custom VM sizing for Worker nodes:${NC}"

      WORKER_CPU=$(read_int_in_range "   Worker vCPU [${W_CPU_MIN}-${W_CPU_MAX}]: " "$W_CPU_MIN" "$W_CPU_MAX")
      WORKER_RAM_GB=$(read_int_in_range "   Worker RAM in GB [${W_RAM_MIN}-${W_RAM_MAX}]: " "$W_RAM_MIN" "$W_RAM_MAX")
      WORKER_DISK_GB=$(read_int_in_range "   Worker Disk in GB [${W_DISK_MIN}-${W_DISK_MAX}]: " "$W_DISK_MIN" "$W_DISK_MAX")

      echo ""
      echo -e "${YELLOW}   Please confirm the worker VM sizing:${NC}"
      echo "   ----------------------------------------"
      echo "   vCPU  : $WORKER_CPU"
      echo "   RAM   : ${WORKER_RAM_GB} GB"
      echo "   Disk  : ${WORKER_DISK_GB} GB"
      echo "   ----------------------------------------"
      echo ""

      if confirm_yn "   Proceed with this worker sizing (Y/N)?"; then
        echo -e "${GREEN}   Worker VM sizing confirmed. Proceeding...${NC}"
        break
      fi

      echo -e "${YELLOW}   Re-entering worker VM sizing...${NC}"
    done
  fi
fi

#----------------------------------------------------------------------------------
# Section Environment Outputs
#
# This section captures VM sizing (vCPU, RAM, Disk) based on the selected cluster
# topology. Defaults are provided, inputs are validated (non-empty, numeric, within
# thresholds), and the user must confirm before proceeding.
#
# Variables set by this section:
# - MASTER_CPU, MASTER_RAM_GB, MASTER_DISK_GB
# - WORKER_CPU, WORKER_RAM_GB, WORKER_DISK_GB
#----------------------------------------------------------------------------------

#Print Separator
echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#----------------------------------------------------------------------------------
# Retrieve Assisted Installer ISO Download URL (Input + Validation)
#----------------------------------------------------------------------------------

echo -e "${YELLOW} Retrieve Assisted Installer ISO Download Command:${NC}"
echo -e "${YELLOW} -------------------------------------------------${NC}"
echo ""
echo -e "${YELLOW} Please paste the FULL wget command exactly as provided by the Assisted Installer.${NC}"
echo "    Example: wget -O discovery_image_xxx.iso 'https://api.openshift.com/api/assisted-images/.../full.iso"
echo ""

# Ensure wget exists
if ! command -v wget >/dev/null 2>&1; then
  echo -e "${RED}   wget is required but not installed. Please install it first.${NC}"
  exit 1
fi

while true; do
  read -rp " - Please enter full wget command: " ISO_WGET_CMD

  # Remove whitespace-only
  ISO_WGET_CMD="$(echo "$ISO_WGET_CMD" | xargs)" 

  # Empty check
  if [[ -z "$ISO_WGET_CMD" ]]; then
    echo -e "${RED}   Input cannot be empty.${NC}"
    continue
  fi

  # Must start with wget
  if ! [[ "$ISO_WGET_CMD" =~ ^wget[[:space:]] ]]; then
    echo -e "${RED}   Invalid command.${NC}"
    echo -e "${RED}   Command must start with 'wget'.${NC}"
    continue
  fi

  # Must contain -O <something>.iso
  if ! [[ "$ISO_WGET_CMD" =~ [[:space:]]-O[[:space:]]+\"?[^\ \"\']+\.iso\"? ]]; then
    echo -e "${RED}   Invalid wget format.${NC}"
    echo -e "${RED}   Command must include '-O <filename>.iso'.${NC}"
    continue
  fi

  # Extract ISO URL (must end with .iso)
  ISO_URL="$(echo "$ISO_WGET_CMD" | grep -Eo 'https?://[^[:space:]'"'"']+\.iso' | head -n1)"

  if [[ -z "$ISO_URL" ]]; then
    echo -e "${RED}   Invalid or missing ISO URL.${NC}"
    echo -e "${RED}   The command must include a valid http(s)://...iso URL.${NC}"
    continue
  fi

  echo ""
  echo -e "   Validating ISO URL reachability..."

  # Reachability check (NO download)
  if ! wget --spider --server-response --max-redirect=5 --timeout=10 --tries=2 "$ISO_URL" >/dev/null 2>&1; then
    echo -e "${RED}   ISO URL is not reachable or access is denied.${NC}"
    echo -e "${RED}   Please re-enter a valid Assisted Installer wget command.${NC}"
    continue
  fi

  echo -e "${GREEN}   ISO download command validated successfully. Proceeding...${NC}"
  break
done

#----------------------------------------------------------------------------------
# Section Environment Outputs
#
# This section collects and validates the Assisted Installer ISO download URL.
# The URL is checked for correct format (http/https) and verified to be reachable.
# The ISO is not downloaded at this stage; it will be retrieved later in the script.
#
# Variables set by this section:
# - ISO_URL : Assisted Installer ISO download Command
#----------------------------------------------------------------------------------

#Print Separator
echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#----------------------------------------------------------------------------------
# Provide all retrieved info and confirm before proceeding
#----------------------------------------------------------------------------------

echo -e "${YELLOW} ====== Final Configuration Summary ======${NC}"
echo ""

echo -e "${CYAN} - vCenter Configuration & Info:${NC}"
echo "   vCenter URL        : $GOVC_URL"
echo "   vCenter Username   : $GOVC_USERNAME"
echo "   vCenter Password   : $GOVC_PASSWORD"
echo "   Datacenter Name    : $DC_NAME"
echo "   Datacenter Path    : $GOVC_DATACENTER_PATH"
echo "   VM Folder Name     : $GOVC_VM_FOLDER_NAME"
echo "   VM Folder Path     : $GOVC_VM_FOLDER_PATH"
echo "   Datastore Name     : $GOVC_DATASTORE_NAME"
echo "   Datastore Path     : $GOVC_DATASTORE_PATH"
echo "   Network Name       : $GOVC_NETWORK_NAME"
echo "   Network Path       : $GOVC_NETWORK_PATH"
echo ""

echo -e "${CYAN} - OpenShift Configuration:${NC}"
echo "   OpenShift Release  : $OCP_RELEASE"
echo "   ISO Download WGET  : $ISO_WGET_CMD"
echo "   Cluster Mode       : $CLUSTER_MODE"
echo "   Master Nodes       : $MASTER_COUNT"
echo "   Worker Nodes       : $WORKER_COUNT"
echo ""

echo -e "${CYAN} - VM Sizing:${NC}"

if [[ "$CLUSTER_MODE" == "compact" ]]; then
  echo "   Compact Nodes (Masters act as Workers):"
  echo "   vCPU             : $MASTER_CPU"
  echo "   RAM              : ${MASTER_RAM_GB} GB"
  echo "   Disk             : ${MASTER_DISK_GB} GB"
else
  echo "   Master Nodes:"
  echo "   vCPU             : $MASTER_CPU"
  echo "   RAM              : ${MASTER_RAM_GB} GB"
  echo "   Disk             : ${MASTER_DISK_GB} GB"
  echo ""
  echo "   Worker Nodes:"
  echo "   vCPU             : $WORKER_CPU"
  echo "   RAM              : ${WORKER_RAM_GB} GB"
  echo "   Disk             : ${WORKER_DISK_GB} GB"
fi

echo ""
echo -e "${YELLOW}==========================================${NC}"
echo ""

if confirm_yn "   Proceed with the above configuration and start preparation? (Y/N): "; then
  echo -e "${GREEN}   Configuration confirmed. Proceeding...${NC}"
else
  echo -e "${RED}   Configuration not confirmed.${NC}"
  echo -e "${RED}   Exiting script. Please re-run to modify inputs.${NC}"
  exit 1
fi

#----------------------------------------------------------------------------------
# Full Input Summary and Final Confirmation
#
# This section presents a complete summary of all collected inputs and derived
# configuration values. The user must confirm before the script proceeds with
# any provisioning or automation actions.
#
# Variables reviewed in this section include:
# - Lab environment details
# - vCenter connection details
# - OpenShift release and ISO URL
# - Cluster topology and node counts
# - VM sizing for master and worker nodes
#----------------------------------------------------------------------------------

#Print Separator
echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#########################################################################
####### Retriving Info Complated - Starting Script Activites ############
#########################################################################

echo -e "${GREEN}   Required Info Retrieved. Start Script Activities...${NC}"

#Print Separator
echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#----------------------------------------------------------------------------------
# Download Assisted Installer ISO File
#----------------------------------------------------------------------------------

echo -e "${YELLOW} Downloading Assisted Installer ISO${NC}"
echo -e "${YELLOW} ----------------------------------${NC}"

ISO_DIR="$HOME/assisted-installer-iso"

# Create directory if it does not exist
mkdir -p "$ISO_DIR"

# Download ISO using the exact command provided by the user
$ISO_WGET_CMD

# Extract ISO filename from wget command
ISO_FILENAME="$(echo "$ISO_WGET_CMD" | awk '{for (i=1;i<=NF;i++) if ($i=="-O") print $(i+1)}')"

# Validate download
if [[ ! -f "$ISO_FILENAME" ]]; then
  echo -e "${RED} ERROR: ISO file was not downloaded: $ISO_FILENAME${NC}"
  echo -e "${RED} Please check this issue and try again.${NC}"
  exit 1
fi

# Move ISO to target directory
mv -f "$ISO_FILENAME" "$ISO_DIR/"

ISO_FULL_PATH="$ISO_DIR/$ISO_FILENAME"

echo -e "${GREEN} ISO download completed successfully.${NC}"
echo -e "${GREEN} ISO file path: $ISO_FULL_PATH${NC}"

#Print Separator
echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#----------------------------------------------------------------------------------
# Check and Install govc
#----------------------------------------------------------------------------------

echo -e "${YELLOW} Insallting GOVC CLI${NC}"
echo -e "${YELLOW} -------------------${NC}"

if command -v govc >/dev/null 2>&1; then
  echo -e "${GREEN} GOVC is already installed. Skipping.${NC}"
else
  curl -sL -o - "https://github.com/vmware/govmomi/releases/latest/download/govc_$(uname -s)_$(uname -m).tar.gz" | sudo tar -C /usr/local/bin -xvzf - govc

  echo -e "${GREEN} GOVC installed successfully.${NC}"
fi

#Print Separator
echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#----------------------------------------------------------------------------------
# Install OpenShift oc CLI
#----------------------------------------------------------------------------------

echo -e "${YELLOW} Installing OpenShift oc CLI${NC}"
echo -e "${YELLOW} ---------------------------${NC}"

if command -v oc >/dev/null 2>&1; then
  echo -e "${GREEN} oc CLI is already installed. Skipping.${NC}"
else
  TMP_DIR="$(mktemp -d)"
  OC_TAR="openshift-client-linux.tar.gz"
  OC_URL="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OCP_RELEASE}/${OC_TAR}"

  echo -e "${CYAN} Downloading oc CLI...${NC}"
  wget -q -O "${TMP_DIR}/${OC_TAR}" "$OC_URL"

  echo -e "${CYAN} Extracting oc and kubectl...${NC}"
  tar -xzf "${TMP_DIR}/${OC_TAR}" -C "$TMP_DIR"

  echo -e "${CYAN} Installing binaries to /usr/local/bin...${NC}"
  sudo mv "${TMP_DIR}/oc" "${TMP_DIR}/kubectl" /usr/local/bin/
  sudo chmod +x /usr/local/bin/oc /usr/local/bin/kubectl

  rm -rf "$TMP_DIR"

  echo -e "${GREEN} oc CLI installed successfully.${NC}"
fi

#Print Separator
echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#----------------------------------------------------------------------------------
# Install Helm CLI (Red Hat / OpenShift Mirror)
#----------------------------------------------------------------------------------

echo -e "${YELLOW} Installing Helm CLI${NC}"
echo -e "${YELLOW} --------------------${NC}"

if command -v helm >/dev/null 2>&1; then
  echo -e "${GREEN} Helm is already installed. Skipping.${NC}"
else
  echo -e "${CYAN} Downloading Helm binary from Red Hat mirror...${NC}"
  if ! sudo curl -fsSL https://mirror.openshift.com/pub/openshift-v4/clients/helm/latest/helm-linux-amd64 -o /usr/local/bin/helm; then
    echo -e "${RED} ERROR: Failed to download Helm binary.${NC}"
    echo -e "${RED} Please check the issue and install Helm manually after script complete.${NC}"
  fi

  echo -e "${CYAN} Setting execute permission...${NC}"
  sudo chmod +x /usr/local/bin/helm

  echo -e "${GREEN} Helm installed successfully.${NC}"
fi

echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#----------------------------------------------------------------------------------
# Deploy Required VMs and perform required configuration
#----------------------------------------------------------------------------------

echo -e "${YELLOW} Deploying Required Infrastrcutre For OCP...${NC}"
echo -e "${YELLOW} -------------------------------------------${NC}"
echo ""

#----------------------------------------------------------------------

#----------------------------------------------------------------------------------
# Upload Assisted Installer ISO To vCenter Datastore
# Target: <datastore>/ISO/<iso-file-name>
#----------------------------------------------------------------------------------

echo -e "${CYAN} - Uploading Assisted Installer ISO To Datastore${NC}"

# Expected inputs already set earlier: - ISO_FULL_PATH - ISO_FILENAME - GOVC_DATASTORE_NAME

# Upload to datastore under ISO/<filename> (govc will create the 'ISO' dir if needed)
if ! govc datastore.upload -ds "$GOVC_DATASTORE_PATH" "$ISO_FULL_PATH" "DEMO-LAB-ISO/${ISO_FILENAME}" >/dev/null 2>&1; then
  echo -e "${RED}   ERROR: Failed to upload ISO to datastore.${NC}"
  echo -e "${RED}   Please verify datastore access/permissions and try again.${NC}"
  exit 1
fi

DATASTORE_ISO_PATH="DEMO-LAB-ISO/${ISO_FILENAME}"

echo -e "${GREEN}   ISO uploaded successfully.${NC}"
echo -e "${GREEN}   Datastore ISO path: ${DATASTORE_ISO_PATH}${NC}"

echo ""
echo "   ---------------------------------------------------- "
echo ""

#----------------------------------------------------------------------

#----------------------------------------------------------------------------------
# Deploy VMs (compact vs standard) + attach ISO + enable UUID + connect-at-boot + power on
#----------------------------------------------------------------------------------

echo -e "${CYAN} - Deploying OpenShift Cluster VMs${NC}"
echo ""

VM_LIST=()   # store created VM names so we can list them all at the end

if [[ "$CLUSTER_MODE" == "compact" ]]; then
  echo -e "${CYAN}   Cluster type: Compact (3 nodes) - Creating & Configuring VMs...${NC}"
  echo ""
  for i in 1 2 3; do
    VM_NAME="demo-ocp-mgmt-master-0${i}"
    VM_TYPE="Master"
    create_vm "$VM_NAME" "$MASTER_CPU" "$MASTER_RAM_GB" "$MASTER_DISK_GB" "$i" "$VM_TYPE" 
    VM_LIST+=("$VM_NAME")
    echo ""
  done
else
  echo -e "${CYAN}   Cluster type: Standard (3 masters + ${WORKER_COUNT} workers)${NC}"
  echo -e "${CYAN}   Creating & Configuring VMs...${NC}"
  echo ""
  echo -e "${CYAN}   Creating Master Nodes...${NC}"
  echo ""

  # Masters
  for i in 1 2 3; do
    VM_NAME="demo-ocp-mgmt-master-0${i}"
    VM_TYPE="Master"
    create_vm "$VM_NAME" "$MASTER_CPU" "$MASTER_RAM_GB" "$MASTER_DISK_GB" "$i" "$VM_TYPE" 
    VM_LIST+=("$VM_NAME")
    echo ""
  done

  echo -e "${CYAN}   Creating Worker Nodes...${NC}"
  echo ""

  # Workers
  for i in $(seq 1 "$WORKER_COUNT"); do
    VM_NAME="demo-ocp-mgmt-worker-0${i}"
    VM_TYPE="Worker"
    create_vm "$VM_NAME" "$WORKER_CPU" "$WORKER_RAM_GB" "$WORKER_DISK_GB" "$i" "$VM_TYPE" 
    VM_LIST+=("$VM_NAME")
    echo ""
  done
fi

echo ""
echo -e "${GREEN}   All VMs created successfully.${NC}"

echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

echo -e "${YELLOW} Printing the list of deployed VM and thier info...${NC}"
echo -e "${YELLOW} --------------------------------------------------${NC}"
echo ""

echo " Retrieving Info..."
echo " It may take couple of minutes - Please wait..."
echo ""

sleep 20

printf "%-32s %-20s %-20s\n" " VM Name" " MAC Address" " IP Address"
printf "%-32s %-20s %-20s\n" " --------------------------------" "--------------------" "--------------------"

for vm in "${VM_LIST[@]}"; do
  # Get first NIC MAC
  VM_MAC="$(govc device.info -vm "$vm" 2>/dev/null | awk '/MAC Address:/ {sub(/.*MAC Address:[[:space:]]*/, ""); print; exit}' || true)"
  VM_MAC="${VM_MAC:-N/A}"

  # Get IP (single attempt after sleep)
  VM_IP="$(govc vm.ip "$vm" 2>/dev/null | head -n 1 || true)"
  VM_IP="${VM_IP:-PENDING}"

  printf "%-32s %-20s %-20s\n" " $vm" " $VM_MAC" " $VM_IP"
  sleep 1
done

echo ""
echo -e "${GREEN}   All VMs info are listed.${NC}"

echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#----------------------------------------------------------------------------------
# Dump All Script Variables To File (for reference)
#----------------------------------------------------------------------------------

echo -e "${YELLOW} Dumping all script variables and info into an output file...${NC}"
echo -e "${YELLOW} ------------------------------------------------------------${NC}"
echo ""

SCRIPT_OUTPUT_FILE="$HOME/script-output.txt"

{
  echo "---- vCenter / GOVC ----"
  echo "VCENTER_URL=$VCENTER_URL"
  echo "VCENTER_USERNAME=$VCENTER_USERNAME"
  echo "VCENTER_PASSWORD=$VCENTER_PASSWORD"
  echo "DC_NAME=$DC_NAME"
  echo "GOVC_URL=$GOVC_URL"
  echo "GOVC_USERNAME=$GOVC_USERNAME"
  echo "GOVC_PASSWORD=$GOVC_PASSWORD"
  echo "GOVC_DATACENTER=$GOVC_DATACENTER"
  echo "GOVC_INSECURE=$GOVC_INSECURE"
  echo ""

  echo "---- Paths ----"
  echo "GOVC_VM_FOLDER_PATH=$GOVC_VM_FOLDER_PATH"
  echo "GOVC_VM_FOLDER_NAME=$GOVC_VM_FOLDER_NAME"
  echo "GOVC_DATACENTER_PATH=$GOVC_DATACENTER_PATH"
  echo "GOVC_DATASTORE_NAME=$GOVC_DATASTORE_NAME"
  echo "GOVC_DATASTORE_PATH=$GOVC_DATASTORE_PATH"
  echo "GOVC_NETWORK_NAME=$GOVC_NETWORK_NAME"
  echo "GOVC_NETWORK_PATH=$GOVC_NETWORK_PATH"
  echo ""

  echo "---- OpenShift / ISO ----"
  echo "OCP_RELEASE=$OCP_RELEASE"
  echo "ISO_WGET_CMD=$ISO_WGET_CMD"
  echo "ISO_URL=${ISO_URL:-}"
  echo "ISO_DIR=${ISO_DIR:-}"
  echo "ISO_FILENAME=${ISO_FILENAME:-}"
  echo "ISO_FULL_PATH=${ISO_FULL_PATH:-}"
  echo "DATASTORE_ISO_PATH=${DATASTORE_ISO_PATH:-}"
  echo ""

  echo "---- Cluster Topology ----"
  echo "CLUSTER_TYPE=$CLUSTER_TYPE"
  echo "CLUSTER_MODE=$CLUSTER_MODE"
  echo "MASTER_COUNT=$MASTER_COUNT"
  echo "WORKER_COUNT=$WORKER_COUNT"
  echo ""

  echo "---- VM Sizing ----"
  echo "MASTER_CPU=$MASTER_CPU"
  echo "MASTER_RAM_GB=$MASTER_RAM_GB"
  echo "MASTER_DISK_GB=$MASTER_DISK_GB"
  echo "WORKER_CPU=$WORKER_CPU"
  echo "WORKER_RAM_GB=$WORKER_RAM_GB"
  echo "WORKER_DISK_GB=$WORKER_DISK_GB"
  echo ""

  echo "---- VM List ----"
  if declare -p VM_LIST >/dev/null 2>&1; then
    printf "VM_LIST=("
    printf "'%s' " "${VM_LIST[@]}"
    echo ")"
  else
    echo "VM_LIST="
  fi

  echo ""
  echo "=================================================================================="
  echo ""
} > "$SCRIPT_OUTPUT_FILE"

echo -e "${GREEN} Script variables dumped to: $SCRIPT_OUTPUT_FILE${NC}"

#===================================================================================

#-------------------------------------------------------------
# Print Script Completed
#-------------------------------------------------------------

echo ""
echo -e "${RED}"
echo "  --------------------------------------------------------------------------------  "
echo " | =====================         Script Completed           ===================== | "
echo " | =====================            * Enjoy *               ===================== | "
echo "  --------------------------------------------------------------------------------  "
echo " ================================================================================== "
echo ""
echo -e "${NC}"
echo " ================================================================================== "
echo ""

#===================================================================================