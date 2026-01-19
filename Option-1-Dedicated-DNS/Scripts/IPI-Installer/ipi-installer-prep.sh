#!/usr/bin/env bash

#===================================================================================

#-------------------------------------------------------------
# Add strict bash safety & Set trap to handel script interruption
#-------------------------------------------------------------

set -Eeuo pipefail

trap 'echo -e "\n${RED} ---- Script interrupted. Exiting...${NC}"; exit 1' INT TERM
trap 'rc=$?; echo -e "\n${RED} ---- ERROR: line ${LINENO}: ${BASH_COMMAND} (exit code: ${rc})${NC}" >&2; exit $rc' ERR

#===================================================================================

#-------------------------------------------------------------
# Script Description
#-------------------------------------------------------------

################################################################################
# This script prepares the bastion host in a VMware-based lab environment for
# deploying an OpenShift cluster using the Installer-Provisioned Infrastructure
# (IPI) workflow.
#
# It focuses on collecting and validating user inputs required for an IPI-based
# deployment, generating a customized install-config.yaml from a predefined
# template, and installing the necessary client-side tooling.
#
# The script performs the following high-level tasks:
# - Collects and confirms user-provided cluster, vSphere, and sizing inputs
# - Creates a backup copy of the install-config.yaml template and applies the
#   provided inputs to a working copy in a separate directory
# - Installs required tools on the bastion host (govc, oc, OpenShift installer,
#   and Helm) if they are not already present
# - Optionally executes the OpenShift IPI installer based on user confirmation,
#   or provides the exact command for manual execution
#
# No DNS, load balancer, or external infrastructure services are configured on
# the bastion host. All such services are assumed to be provided externally by
# the lab or platform environment.
#
# This script is intended for Option 2 (IPI Installer) deployments and is safe
# to re-run for preparation and validation purposes.
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

#===================================================================================

#-------------------------------------------------------------
# Print Staring Script Message
#-------------------------------------------------------------

echo -e "${RED}"
echo "  -------------------------------------------------------------------  "
echo " | =========       Dedicated DNS Records Environment       ========= | "
echo " | ----------------------------------------------------------------- | "
echo " |                                                                   | "
echo " | ██╗ ██████╗  ██╗                                                  | "
echo " | ██║ ██╔══██╗ ██║                                                  | "
echo " | ██║ ██████╔╝ ██║                                                  | "
echo " | ██║ ██╔═══╝  ██║                                                  | "
echo " | ██║ ██║      ██║                                                  | "
echo " | ╚═╝ ╚═╝      ╚═╝                                                  | "
echo " | ██╗ ███╗   ██╗ ███████╗ ████████╗  █████╗  ██╗      ██╗           | "
echo " | ██║ ████╗  ██║ ██╔════╝ ╚══██╔══╝ ██╔══██╗ ██║      ██║           | "
echo " | ██║ ██╔██╗ ██║ ███████╗    ██║    ███████║ ██║      ██║           | "
echo " | ██║ ██║╚██╗██║ ╚════██║    ██║    ██╔══██║ ██║      ██║           | "
echo " | ██║ ██║ ╚████║ ███████║    ██║    ██║  ██║ ███████╗ ███████╗      | "
echo " | ╚═╝ ╚═╝  ╚═══╝ ╚══════╝    ╚═╝    ╚═╝  ╚═╝ ╚══════╝ ╚══════╝      | "
echo " | ██████╗  ██████╗  ███████╗ ██████╗                                | "
echo " | ██╔══██╗ ██╔══██╗ ██╔════╝ ██╔══██╗                               | "
echo " | ██████╔╝ ██████╔╝ █████╗   ██████╔╝                               | "
echo " | ██╔═══╝  ██╔══██╗ ██╔══╝   ██╔═══╝                                | "
echo " | ██║      ██║  ██║ ███████╗ ██║                                    | "
echo " | ╚═╝      ╚═╝  ╚═╝ ╚══════╝ ╚═╝                                    | "
echo "  -------------------------------------------------------------------  "
echo ""
echo " --- Starting the IPI Installer Preparation automation script For Dedicated DNS Enviroenemtn..."
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
  echo ""
  VCENTER_URL=$(read_non_empty "       Enter vCenter URL (e.g. vc.example.com): ")
  VCENTER_USERNAME=$(read_non_empty "       Enter vCenter username: ")
  VCENTER_PASSWORD=$(read_non_empty "       Enter vCenter password: ")
  VCENTER_DC_NAME=$(read_non_empty "       Enter vCenter Datacenter Name (e.g. SDDC-Datacenter): ")
  VCENTER_CLUSTER_NAME=$(read_non_empty "       Enter vCenter Cluster Name (e.g. Cluster-1): ")
  VCENTER_VM_FOLDER_NAME=$(read_non_empty "       Enter vCenter VM Folder Name (e.g. sandbox-r5vnx): ")
  VCENTER_DS_NAME=$(read_non_empty "       Enter vCenter Datastore Name (e.g. workload_share_yBaQN): ")
  VCENTER_NET_NAME=$(read_non_empty "       Enter vCenter Network Segment Name (e.g. segment-sandbox-r5vnx): ")
  LAB_MAIN_DOMAIN=$(read_non_empty "       Enter Lab Main Domain (e.g domain.example.com): ")
  LAB_ID=$(read_non_empty "       Enter Lab ID (e.g. r5vnx): ")
  API_VIP=$(read_non_empty "       Enter OpenShift API VIP IP (e.g. 192.168.x.x): ")
  APPS_VIP=$(read_non_empty "       Enter OpenShift APPs VIP IP (e.g. 192.168.x.x): ")
  OCP_RELEASE=$(read_non_empty "       Enter OpenShift release (e.g. 4.20.4): ")
  echo ""

  # Extract Object Path from user input
  VCENTER_DC_PATH="/${VCENTER_DC_NAME}"
  VCENTER_CLUSTER_PATH="/${VCENTER_DC_NAME}/host/${VCENTER_CLUSTER_NAME}"
  VCENTER_VM_FOLDER_PATH="/${VCENTER_DC_NAME}/vm/Workloads/${VCENTER_VM_FOLDER_NAME}"
  VCENTER_DS_PATH="/${VCENTER_DC_NAME}/datastore/${VCENTER_DS_NAME}"
  VCENTER_NET_PATH="/${VCENTER_DC_NAME}/network/${VCENTER_NET_NAME}"

  # Adding ResourcePool Variable From the info provided by User
  VCENTER_RP_NAME="Resources"
  VCENTER_RP_PATH="${VCENTER_CLUSTER_PATH}/${VCENTER_RP_NAME}"

  echo -e "${YELLOW} - Please review the provided information below & confirm (Y/N):${NC}"
  echo "   ----------------------------------------"
  echo "   vCenter URL         : $VCENTER_URL"
  echo "   vCenter Username    : $VCENTER_USERNAME"
  echo "   vCenter Password    : $VCENTER_PASSWORD"
  echo "   Datacenter Name     : $VCENTER_DC_NAME"
  echo "   Datacenter Path     : $VCENTER_DC_PATH"
  echo "   Cluster Name        : $VCENTER_CLUSTER_NAME"
  echo "   Cluster Path        : $VCENTER_CLUSTER_PATH"
  echo "   Resource Pool Name  : $VCENTER_RP_NAME"
  echo "   Resource Pool Path  : $VCENTER_RP_PATH"
  echo "   VM Folder Name      : $VCENTER_VM_FOLDER_NAME"
  echo "   VM Folder Path      : $VCENTER_VM_FOLDER_PATH"
  echo "   Datastore Name      : $VCENTER_DS_NAME"
  echo "   Datastore Path      : $VCENTER_DS_PATH"
  echo "   Network Name        : $VCENTER_NET_NAME"
  echo "   Network Path        : $VCENTER_NET_PATH"
  echo "   Lab Main Domain     : $LAB_MAIN_DOMAIN"
  echo "   Lab ID              : $LAB_ID"
  echo "   OpenShift API VIP   : $API_VIP"
  echo "   OpenShift APPs VIP  : $APPS_VIP"
  echo "   OpenShift Release   : $OCP_RELEASE"
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

#----------------------------------------------------------------------------------
# Section Environment Outputs
#
# This section captures all required lab, networking, and vCenter configuration
# details needed to prepare an OpenShift IPI deployment on VMware vSphere.
#
# The collected values are later used to:
# - Populate the install-config.yaml file for the IPI installer
# - Configure vSphere-related paths and resources
# - Install and configure required tooling (govc, oc, helm, openshift-installer)
#
# Variables set by this section:
# - VCENTER_URL            : vCenter server URL
# - VCENTER_USERNAME       : vCenter username
# - VCENTER_PASSWORD       : vCenter password
# - VCENTER_DC_NAME        : vCenter Datacenter name
# - VCENTER_DC_PATH        : Full vCenter Datacenter inventory path
# - VCENTER_CLUSTER_NAME   : vCenter Cluster name
# - VCENTER_CLUSTER_PATH   : Full vCenter Cluster inventory path
# - VCENTER_RP_NAME        : Resource Pool name (default: Resources)
# - VCENTER_RP_PATH        : Full Resource Pool inventory path
# - VCENTER_VM_FOLDER_NAME : VM folder name
# - VCENTER_VM_FOLDER_PATH : Full VM folder inventory path
# - VCENTER_DS_NAME        : Datastore name
# - VCENTER_DS_PATH        : Full datastore inventory path
# - VCENTER_NET_NAME       : Network / port group name
# - VCENTER_NET_PATH       : Full network inventory path
# - LAB_MAIN_DOMAIN        : Base domain for the OpenShift cluster
# - LAB_ID                 : Lab ID / cluster name
# - API_VIP                : OpenShift API virtual IP
# - APPS_VIP               : OpenShift Ingress (apps) virtual IP
# - OCP_RELEASE            : OpenShift release version
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
# Provide all retrieved info and confirm before proceeding
#----------------------------------------------------------------------------------

echo -e "${YELLOW} ====== Final Configuration Summary ======${NC}"
echo ""

echo -e "${CYAN} - vCenter Configuration & Lab Info:${NC}"
echo "   vCenter URL         : $VCENTER_URL"
echo "   vCenter Username    : $VCENTER_USERNAME"
echo "   vCenter Password    : $VCENTER_PASSWORD"
echo "   Datacenter Name     : $VCENTER_DC_NAME"
echo "   Datacenter Path     : $VCENTER_DC_PATH"
echo "   Cluster Name        : $VCENTER_CLUSTER_NAME"
echo "   Cluster Path        : $VCENTER_CLUSTER_PATH"
echo "   Resource Pool Name  : $VCENTER_RP_NAME"
echo "   Resource Pool Path  : $VCENTER_RP_PATH"
echo "   VM Folder Name      : $VCENTER_VM_FOLDER_NAME"
echo "   VM Folder Path      : $VCENTER_VM_FOLDER_PATH"
echo "   Datastore Name      : $VCENTER_DS_NAME"
echo "   Datastore Path      : $VCENTER_DS_PATH"
echo "   Network Name        : $VCENTER_NET_NAME"
echo "   Network Path        : $VCENTER_NET_PATH"
echo "   Lab Main Domain     : $LAB_MAIN_DOMAIN"
echo "   Lab ID              : $LAB_ID"
echo ""

echo -e "${CYAN} - OpenShift / IPI Configuration:${NC}"
echo "   OpenShift Release   : $OCP_RELEASE"
echo "   API VIP             : $API_VIP"
echo "   APPs VIP            : $APPS_VIP"
echo "   Cluster Mode        : $CLUSTER_MODE"
echo "   Master Nodes        : $MASTER_COUNT"
echo "   Worker Nodes        : $WORKER_COUNT"
echo ""

echo -e "${CYAN} - VM Sizing (Install-Config Values):${NC}"
if [[ "$CLUSTER_MODE" == "compact" ]]; then
  echo "   Compact Nodes (Masters act as Workers):"
  echo "   vCPU               : $MASTER_CPU"
  echo "   RAM                : ${MASTER_RAM_GB} GB"
  echo "   Disk               : ${MASTER_DISK_GB} GB"
else
  echo "   Master Nodes:"
  echo "   vCPU               : $MASTER_CPU"
  echo "   RAM                : ${MASTER_RAM_GB} GB"
  echo "   Disk               : ${MASTER_DISK_GB} GB"
  echo ""
  echo "   Worker Nodes:"
  echo "   vCPU               : $WORKER_CPU"
  echo "   RAM                : ${WORKER_RAM_GB} GB"
  echo "   Disk               : ${WORKER_DISK_GB} GB"
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
# configuration values. The user must confirm before the script proceeds with:
# - Backing up + generating a new install-config.yaml
# - Installing required tooling (govc, oc, openshift-install, helm)
# - Optionally running openshift-install (if user chooses)
#
# Variables reviewed in this section include:
# - vCenter / lab environment details
# - OpenShift release + VIPs
# - Cluster topology and node counts
# - VM sizing for control-plane and compute
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
# Check and Install yq (YAML Processor)
#----------------------------------------------------------------------------------

echo -e "${YELLOW} Installing yq CLI${NC}"
echo -e "${YELLOW} -------------------${NC}"

if command -v yq >/dev/null 2>&1; then
  echo -e "${GREEN} yq is already installed. Skipping.${NC}"
else
  if ! sudo curl -sL \
      "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" -o /usr/local/bin/yq; then
    echo -e "${RED} ERROR: Failed to download yq binary.${NC}"
    echo -e "${RED} Check network access and GitHub connectivity.${NC}"
    echo -e "${RED} yq is mandatory for this script to continue. Please check issue and try again.${NC}"
    exit 1
  fi

  sudo chmod +x /usr/local/bin/yq

  # Final validation
  if ! command -v yq >/dev/null 2>&1; then
    echo -e "${RED} ERROR: yq installation completed but command is not available.${NC}"
    exit 1
  fi

  echo -e "${GREEN} yq installed successfully.${NC}"
fi

#Print Separator
echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#----------------------------------------------------------------------------------
# Check and Install govc
#----------------------------------------------------------------------------------

echo -e "${YELLOW} Installing GOVC CLI${NC}"
echo -e "${YELLOW} -------------------${NC}"

if command -v govc >/dev/null 2>&1; then
  echo -e "${GREEN} GOVC is already installed. Skipping.${NC}"
else
  if ! curl -sL "https://github.com/vmware/govmomi/releases/latest/download/govc_$(uname -s)_$(uname -m).tar.gz" | sudo tar -xz -C /usr/local/bin govc; then
    echo -e "${RED} ERROR: Failed to download or install GOVC CLI.${NC}"
    echo -e "${RED} Check network access, permissions, and system architecture.${NC}"
    echo -e "${RED} Please check the issue and install GOVC manually [If Required] after script complete.${NC}"
  fi

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
echo ""

if command -v oc >/dev/null 2>&1; then
  echo -e "${GREEN} oc CLI is already installed. Skipping.${NC}"
else
  echo -e "${CYAN} Downloading and installing oc CLI (OpenShift ${OCP_RELEASE})...${NC}"

  if ! curl -sL "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OCP_RELEASE}/openshift-client-linux.tar.gz" | sudo tar -xz -C /usr/local/bin oc kubectl; then
    echo -e "${RED} ERROR: Failed to download or install oc CLI.${NC}"
    echo -e "${RED} Possible causes:${NC}"
    echo -e "${RED}  - Invalid OpenShift release version (${OCP_RELEASE})${NC}"
    echo -e "${RED}  - Network / proxy / firewall issue${NC}"
    echo -e "${RED}  - Insufficient permissions to write to /usr/local/bin${NC}"
    echo -e "${RED} Please check the issue and install oc CLI manually after script complete.${NC}"
  fi

  sudo chmod +x /usr/local/bin/oc /usr/local/bin/kubectl
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
# Create Working Install Directory + Generate install-config.yaml
#----------------------------------------------------------------------------------

echo -e "${YELLOW} Preparing install-config.yaml For IPI${NC}"
echo -e "${YELLOW} ------------------------------------${NC}"
echo ""

# 1) Define working directory (cluster name = LAB_ID)
INSTALL_BASE_DIR="openshift-install-dir"
CLUSTER_NAME="${LAB_ID}"
INSTALL_DIR="${INSTALL_BASE_DIR}/${CLUSTER_NAME}"

# 2) Template path (relative to where you run the script)
INSTALL_CONFIG_TEMPLATE="RH-DEMO-OCP-ON-VM-PREPARATION/Option-1-Dedicated-DNS/Files/IPI-Installer/install-config/install-config.yaml"

echo "   Creating install directory: ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"

# 3) Validate template exists
if [[ ! -f "${INSTALL_CONFIG_TEMPLATE}" ]]; then
  echo -e "${RED} ERROR: install-config template not found at:${NC}"
  echo -e "${RED} ${INSTALL_CONFIG_TEMPLATE}${NC}"
  echo -e "${RED} Run the script from the correct location or fix the template path.${NC}"
  exit 1
fi


# 5) Copy template into working dir (keep a backup copy too)
echo "   Copying install-config template..."
cp -f "${INSTALL_CONFIG_TEMPLATE}" "${INSTALL_DIR}/install-config.yaml"
cp -f "${INSTALL_DIR}/install-config.yaml" "${INSTALL_DIR}/install-config.yaml.bak"
echo "      Template copied to: ${INSTALL_DIR}/install-config.yaml"

# 6) Apply user inputs into install-config.yaml
echo "   Updating install-config.yaml with provided inputs..."

# cluster identity
yq -i ".metadata.name = \"${CLUSTER_NAME}\"" "${INSTALL_DIR}/install-config.yaml"
yq -i ".baseDomain = \"${LAB_MAIN_DOMAIN}\"" "${INSTALL_DIR}/install-config.yaml"

# networking VIPs (for dedicated DNS env)
yq -i ".platform.vsphere.apiVIP = \"${API_VIP}\"" "${INSTALL_DIR}/install-config.yaml"
yq -i ".platform.vsphere.ingressVIP = \"${APPS_VIP}\"" "${INSTALL_DIR}/install-config.yaml"

# vSphere connectivity + inventory paths
yq -i ".platform.vsphere.vcenter = \"${VCENTER_URL}\"" "${INSTALL_DIR}/install-config.yaml"
yq -i ".platform.vsphere.username = \"${VCENTER_USERNAME}\"" "${INSTALL_DIR}/install-config.yaml"
yq -i ".platform.vsphere.password = \"${VCENTER_PASSWORD}\"" "${INSTALL_DIR}/install-config.yaml"

yq -i ".platform.vsphere.datacenter = \"${VCENTER_DC_NAME}\"" "${INSTALL_DIR}/install-config.yaml"
yq -i ".platform.vsphere.cluster = \"${VCENTER_CLUSTER_NAME}\"" "${INSTALL_DIR}/install-config.yaml"
yq -i ".platform.vsphere.resourcePool = \"${VCENTER_RP_PATH}\"" "${INSTALL_DIR}/install-config.yaml"
yq -i ".platform.vsphere.folder = \"${VCENTER_VM_FOLDER_PATH}\"" "${INSTALL_DIR}/install-config.yaml"
yq -i ".platform.vsphere.datastore = \"${VCENTER_DS_NAME}\"" "${INSTALL_DIR}/install-config.yaml"
yq -i ".platform.vsphere.network = \"${VCENTER_NET_NAME}\"" "${INSTALL_DIR}/install-config.yaml"

# replicas (compact vs standard)
if [[ "${CLUSTER_MODE}" == "compact" ]]; then
  yq -i ".controlPlane.replicas = 3" "${INSTALL_DIR}/install-config.yaml"
  yq -i ".compute = []" "${INSTALL_DIR}/install-config.yaml"
else
  yq -i ".controlPlane.replicas = 3" "${INSTALL_DIR}/install-config.yaml"
  yq -i ".compute[0].replicas = ${WORKER_COUNT}" "${INSTALL_DIR}/install-config.yaml"
fi

# sizing (controlPlane + compute)
yq -i ".controlPlane.platform.vsphere.cpus = ${MASTER_CPU}" "${INSTALL_DIR}/install-config.yaml"
yq -i ".controlPlane.platform.vsphere.memoryMB = ${MASTER_RAM_GB} * 1024" "${INSTALL_DIR}/install-config.yaml"
yq -i ".controlPlane.platform.vsphere.osDisk.diskSizeGB = ${MASTER_DISK_GB}" "${INSTALL_DIR}/install-config.yaml"

if [[ "${CLUSTER_MODE}" != "compact" ]]; then
  yq -i ".compute[0].platform.vsphere.cpus = ${WORKER_CPU}" "${INSTALL_DIR}/install-config.yaml"
  yq -i ".compute[0].platform.vsphere.memoryMB = ${WORKER_RAM_GB} * 1024" "${INSTALL_DIR}/install-config.yaml"
  yq -i ".compute[0].platform.vsphere.osDisk.diskSizeGB = ${WORKER_DISK_GB}" "${INSTALL_DIR}/install-config.yaml"
fi

echo -e "${GREEN}   install-config.yaml updated successfully.${NC}"
echo "      Working file : ${INSTALL_DIR}/install-config.yaml"
echo "      Backup file  : ${INSTALL_DIR}/install-config.yaml.bak"

#Print Separator
echo ""
echo " ================================================================================== "
echo ""