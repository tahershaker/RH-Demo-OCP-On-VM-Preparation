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

# Unset GOVC environment variables (avoid stale sessions)
unset GOVC_URL GOVC_USERNAME GOVC_PASSWORD GOVC_INSECURE GOVC_DATACENTER

# Unset script variables (avoid stale values if sourced or reused)
unset VCENTER_URL VCENTER_USERNAME VCENTER_PASSWORD
unset VCENTER_DC_NAME VCENTER_CLUSTER_NAME VCENTER_VM_FOLDER_NAME VCENTER_DS_NAME VCENTER_NET_NAME
unset VCENTER_DC_PATH VCENTER_CLUSTER_PATH VCENTER_VM_FOLDER_PATH VCENTER_DS_PATH VCENTER_NET_PATH
unset VCENTER_RP_NAME VCENTER_RP_PATH
unset LAB_MAIN_DOMAIN LAB_ID API_VIP APPS_VIP OCP_RELEASE
unset PULL_SECRET SSH_KEY
unset CLUSTER_MODE CLUSTER_TYPE MASTER_COUNT WORKER_COUNT
unset MASTER_CPU MASTER_RAM_GB MASTER_DISK_GB WORKER_CPU WORKER_RAM_GB WORKER_DISK_GB
unset CPU_MIN CPU_MAX RAM_MIN RAM_MAX DISK_MIN DISK_MAX
unset M_CPU_MIN M_CPU_MAX M_RAM_MIN M_RAM_MAX M_DISK_MIN M_DISK_MAX
unset W_CPU_MIN W_CPU_MAX W_RAM_MIN W_RAM_MAX W_DISK_MIN W_DISK_MAX
unset REPO_BASE_DIR INSTALL_CONFIG_TEMPLATE INSTALL_BASE_DIR CLUSTER_NAME INSTALL_DIR INSTALL_CONFIG_WORKING
unset MASTER_RAM_MB_YQ WORKER_RAM_MB_YQ
unset BACKUP_FILE TIMESTAMP

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

# Function to readh json file from user input (pull secret)
read_json() {
  local prompt="$1"
  local value

  # Print prompts to STDERR so they appear even inside $(...)
  echo -e "${YELLOW}${prompt}${NC}" >&2
  echo -e "${GREY}       Paste the full JSON, then press Ctrl+D when done.${NC}" >&2

  # Read from STDIN until EOF (Ctrl+D)
  value="$(cat)"

  # Reject empty / whitespace-only
  if [[ -z "${value//[[:space:]]/}" ]]; then
    echo -e "${RED}       ERROR: Input cannot be empty.${NC}" >&2
    return 1
  fi

  # Return raw content exactly
  printf '%s' "$value"
}

#------------------------------------------------------------------------------

# Function to read ssh key from user input
read_ssh_key() {
  local prompt="$1"
  local value

  while true; do
    read -r -p "$prompt" value

    # Reject empty / whitespace-only
    if [[ -z "${value//[[:space:]]/}" ]]; then
      echo -e "${RED}       ERROR: SSH key cannot be empty.${NC}" >&2
      continue
    fi

    # Basic sanity check (good enough for public keys)
    if [[ ! "$value" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]]; then
      echo -e "${RED}       ERROR: This does not look like a valid SSH public key.${NC}" >&2
      echo -e "${RED}       Example: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... user@host${NC}" >&2
      continue
    fi

    printf '%s' "$value"
    return 0
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
  PULL_SECRET="$(read_json "       Enter Red Hat Pull Secret (JSON)")"
  echo ""
  SSH_KEY=$(read_ssh_key "       Enter SSH Key: ")
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
  echo -e "${CYAN} Downloading and installing yq...${NC}"
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

  echo -e "${GREEN} yq installed successfully. Proceeding...${NC}"
fi

#Print Separator
echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#----------------------------------------------------------------------------------
# Check and Install Openshift-Installer
#----------------------------------------------------------------------------------

echo -e "${YELLOW} Installing OpenShift Installer (openshift-install)${NC}"
echo -e "${YELLOW} --------------------------------------------------${NC}"
echo ""

if command -v openshift-install >/dev/null 2>&1; then
  echo -e "${GREEN} openshift-install is already installed. Skipping.${NC}"
else
  echo -e "${CYAN} Downloading and installing openshift-install (OpenShift ${OCP_RELEASE})...${NC}"
  if ! curl -sL "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OCP_RELEASE}/openshift-install-linux.tar.gz" | sudo tar -xz -C /usr/local/bin openshift-install; then
    echo -e "${RED} ERROR: Failed to download or install openshift-install.${NC}"
    echo -e "${RED} Possible causes:${NC}"
    echo -e "${RED}  - Invalid OpenShift release version (${OCP_RELEASE})${NC}"
    echo -e "${RED}  - Network / proxy / firewall issue${NC}"
    echo -e "${RED}  - Insufficient permissions to write to /usr/local/bin${NC}"
    echo -e "${RED} Please check the issue and install OpenShift Installer manually after script complete.${NC}"
  fi
  sudo chmod +x /usr/local/bin/openshift-install
  echo -e "${GREEN} openshift-install installation activity completed. Proceeding...${NC}"
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

  echo -e "${GREEN} GOVC installation activity completed. Proceeding...${NC}"
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
  echo -e "${GREEN} oc CLI installation activity completed. Proceeding...${NC}"
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

  echo -e "${GREEN} Helm installation activity completed. Proceeding...${NC}"
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

# Expected repo location
REPO_BASE_DIR="${HOME}/RH-Demo-OCP-On-VM-Preparation"

# Template path inside repo
INSTALL_CONFIG_TEMPLATE="${REPO_BASE_DIR}/Option-1-Dedicated-DNS/Files/IPI-Installer/install-config.yaml"

# Working directory for OpenShift installer
INSTALL_BASE_DIR="${HOME}/openshift-install-dir"
CLUSTER_NAME="${LAB_ID}"
INSTALL_DIR="${INSTALL_BASE_DIR}/${CLUSTER_NAME}"

echo -e "${CYAN} Preparing OpenShift install-config working directory${NC}"

# 1) Validate repo exists
echo "   Verifying repo exists in the expected path: ${REPO_BASE_DIR}"
if [[ ! -d "${REPO_BASE_DIR}" ]]; then
  echo -e "${RED} ERROR: Required Git repository not found.${NC}"
  echo -e "${RED} Expected location: ${REPO_BASE_DIR}${NC}"
  echo -e "${RED} Please clone the repository into your HOME directory and try again.${NC}"
  exit 1
fi
echo "      Verified. Proceeding..."

# 2) Validate install-config template exists
echo "   Verifying install-config template exists in the expected path: ~/<repo-path>/Option-1-Dedicated-DNS/Files/IPI-Installer/install-config.yaml"
if [[ ! -f "${INSTALL_CONFIG_TEMPLATE}" ]]; then
  echo -e "${RED} ERROR: install-config.yaml template not found.${NC}"
  echo -e "${RED} Expected path: ${INSTALL_CONFIG_TEMPLATE}${NC}"
  echo -e "${RED} Please do not change the cloned repo structure. Please verify the repository structure and template location and try again.${NC}"
  exit 1
fi
echo "      Verified. Proceeding..."

# 3) Create working directory
echo "   Creating install directory: ${INSTALL_DIR}"
if [[ -d "${INSTALL_DIR}" ]]; then
  echo "      Install directory already exists. Proceeding..."
else
  mkdir -p "${INSTALL_DIR}"
  echo "      Created. Proceeding..."
fi

# 4) Copy template to working directory
echo "   Copying install-config.yaml template..."
INSTALL_CONFIG_WORKING="${INSTALL_DIR}/install-config.yaml"
if [[ -f "${INSTALL_CONFIG_WORKING}" ]]; then
  TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
  BACKUP_FILE="${INSTALL_DIR}/install-config.yaml-old-${TIMESTAMP}"
  echo "      Existing install-config.yaml detected. Backing up current file..."
  mv "${INSTALL_CONFIG_WORKING}" "${BACKUP_FILE}"
  echo "      Backup completed. Backup file name is ${BACKUP_FILE}"
fi
cp "${INSTALL_CONFIG_TEMPLATE}" "${INSTALL_CONFIG_WORKING}"
echo "      Install-config Copied. Working directory: ${INSTALL_CONFIG_WORKING}"

# 6) Apply user inputs into install-config.yaml
echo "   Updating install-config.yaml with provided inputs..."

# cluster identity
yq -i ".metadata.name = \"${LAB_ID}\"" "${INSTALL_CONFIG_WORKING}"
yq -i ".baseDomain = \"${LAB_MAIN_DOMAIN}\"" "${INSTALL_CONFIG_WORKING}"

# VIPs (template uses arrays)
yq -i ".platform.vsphere.apiVIPs[0] = \"${API_VIP}\"" "${INSTALL_CONFIG_WORKING}"
yq -i ".platform.vsphere.ingressVIPs[0] = \"${APPS_VIP}\"" "${INSTALL_CONFIG_WORKING}"

# vSphere failureDomain (server + topology paths/names)
yq -i ".platform.vsphere.failureDomains[0].server = \"${VCENTER_URL}\"" "${INSTALL_CONFIG_WORKING}"
yq -i ".platform.vsphere.failureDomains[0].topology.datacenter = \"${VCENTER_DC_NAME}\"" "${INSTALL_CONFIG_WORKING}"
yq -i ".platform.vsphere.failureDomains[0].topology.computeCluster = \"${VCENTER_CLUSTER_PATH}\"" "${INSTALL_CONFIG_WORKING}"
yq -i ".platform.vsphere.failureDomains[0].topology.resourcePool = \"${VCENTER_RP_PATH}\"" "${INSTALL_CONFIG_WORKING}"
yq -i ".platform.vsphere.failureDomains[0].topology.folder = \"${VCENTER_VM_FOLDER_PATH}\"" "${INSTALL_CONFIG_WORKING}"
yq -i ".platform.vsphere.failureDomains[0].topology.datastore = \"${VCENTER_DS_PATH}\"" "${INSTALL_CONFIG_WORKING}"
yq -i ".platform.vsphere.failureDomains[0].topology.networks[0] = \"${VCENTER_NET_NAME}\"" "${INSTALL_CONFIG_WORKING}"

# vSphere vcenters (server + creds + datacenters list)
yq -i ".platform.vsphere.vcenters[0].server = \"${VCENTER_URL}\"" "${INSTALL_CONFIG_WORKING}"
yq -i ".platform.vsphere.vcenters[0].user = \"${VCENTER_USERNAME}\"" "${INSTALL_CONFIG_WORKING}"
yq -i ".platform.vsphere.vcenters[0].password = \"${VCENTER_PASSWORD}\"" "${INSTALL_CONFIG_WORKING}"
yq -i ".platform.vsphere.vcenters[0].datacenters[0] = \"${VCENTER_DC_NAME}\"" "${INSTALL_CONFIG_WORKING}"

# replicas (compact vs standard)
yq -i ".controlPlane.replicas = 3" "${INSTALL_CONFIG_WORKING}"

# check cluster type and set the replicas for compute
if [[ "${CLUSTER_MODE}" == "compact" ]]; then
  yq -i ".compute[0].replicas = 0" "${INSTALL_CONFIG_WORKING}"
else
  yq -i ".compute[0].replicas = ${WORKER_COUNT}" "${INSTALL_CONFIG_WORKING}"
fi

# sizing (controlPlane)
MASTER_RAM_MB_YQ=$((MASTER_RAM_GB * 1024))
WORKER_RAM_MB_YQ=$((WORKER_RAM_GB * 1024))
yq -i ".controlPlane.platform.vsphere.cpus = ${MASTER_CPU}" "${INSTALL_CONFIG_WORKING}"
yq -i ".controlPlane.platform.vsphere.memoryMB = ${MASTER_RAM_MB_YQ}" "${INSTALL_CONFIG_WORKING}"
yq -i ".controlPlane.platform.vsphere.osDisk.diskSizeGB = ${MASTER_DISK_GB}" "${INSTALL_CONFIG_WORKING}"
yq -i ".compute[0].platform.vsphere.cpus = ${WORKER_CPU}" "${INSTALL_CONFIG_WORKING}"
yq -i ".compute[0].platform.vsphere.memoryMB = ${WORKER_RAM_MB_YQ}" "${INSTALL_CONFIG_WORKING}"
yq -i ".compute[0].platform.vsphere.osDisk.diskSizeGB = ${WORKER_DISK_GB}" "${INSTALL_CONFIG_WORKING}"

# pull secret and ssh key
export PULL_SECRET
export SSH_KEY
yq -i '.pullSecret = strenv(PULL_SECRET)' "${INSTALL_CONFIG_WORKING}"
yq -i '.sshKey = strenv(SSH_KEY)' "${INSTALL_CONFIG_WORKING}"

echo "      install-config.yaml updated successfully. Proceeding..."

# take a backup of this file
echo "   Taking a backup of the install-config yaml file."
BACKUP_FILE="${INSTALL_DIR}/install-config.yaml.bak.$(date +%Y%m%d-%H%M%S)"
cp "${INSTALL_DIR}/install-config.yaml" "${BACKUP_FILE}"
echo "      Backup completed successfully. Proceeding..."
echo ""

echo -e "${GREEN}   install-config.yaml updated successfully.${NC}"
echo "      Working file : ${INSTALL_DIR}/install-config.yaml"
echo "      Backup file  : ${BACKUP_FILE}"

#Print Separator
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

SCRIPT_OUTPUT_FILE="$HOME/script-output-ipi.txt"

{
  echo "---- vCenter / Lab ----"
  echo "VCENTER_URL=$VCENTER_URL"
  echo "VCENTER_USERNAME=$VCENTER_USERNAME"
  echo "VCENTER_PASSWORD=$VCENTER_PASSWORD"
  echo "VCENTER_DC_NAME=$VCENTER_DC_NAME"
  echo "VCENTER_CLUSTER_NAME=$VCENTER_CLUSTER_NAME"
  echo "VCENTER_VM_FOLDER_NAME=$VCENTER_VM_FOLDER_NAME"
  echo "VCENTER_DS_NAME=$VCENTER_DS_NAME"
  echo "VCENTER_NET_NAME=$VCENTER_NET_NAME"
  echo "LAB_MAIN_DOMAIN=$LAB_MAIN_DOMAIN"
  echo "LAB_ID=$LAB_ID"
  echo "API_VIP=$API_VIP"
  echo "APPS_VIP=$APPS_VIP"
  echo "OCP_RELEASE=$OCP_RELEASE"
  echo ""

  echo "---- Derived vSphere Paths ----"
  echo "VCENTER_DC_PATH=$VCENTER_DC_PATH"
  echo "VCENTER_CLUSTER_PATH=$VCENTER_CLUSTER_PATH"
  echo "VCENTER_RP_NAME=$VCENTER_RP_NAME"
  echo "VCENTER_RP_PATH=$VCENTER_RP_PATH"
  echo "VCENTER_VM_FOLDER_PATH=$VCENTER_VM_FOLDER_PATH"
  echo "VCENTER_DS_PATH=$VCENTER_DS_PATH"
  echo "VCENTER_NET_PATH=$VCENTER_NET_PATH"
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

  echo "---- install-config working paths ----"
  echo "REPO_BASE_DIR=${REPO_BASE_DIR:-}"
  echo "INSTALL_CONFIG_TEMPLATE=${INSTALL_CONFIG_TEMPLATE:-}"
  echo "INSTALL_BASE_DIR=${INSTALL_BASE_DIR:-}"
  echo "CLUSTER_NAME=${CLUSTER_NAME:-}"
  echo "INSTALL_DIR=${INSTALL_DIR:-}"
  echo "INSTALL_CONFIG_WORKING=${INSTALL_CONFIG_WORKING:-}"
  echo ""

  echo "---- Credentials (Plain Text) ----"
  echo "PULL_SECRET=$PULL_SECRET"
  echo "SSH_KEY=$SSH_KEY"
  echo ""

  echo "=================================================================================="
  echo ""
} > "$SCRIPT_OUTPUT_FILE"

echo -e "${GREEN} Script variables dumped to: $SCRIPT_OUTPUT_FILE${NC}"

#Print Separator
echo ""
echo " ================================================================================== "
echo ""

#===================================================================================

#----------------------------------------------------------------------------------
# Print OpenShift Installer Command (Manual Execution)
#----------------------------------------------------------------------------------

echo -e "${YELLOW} OpenShift Cluster Creation Command${NC}"
echo -e "${YELLOW} ----------------------------------${NC}"
echo ""

echo -e "${CYAN} All required tools have been installed and the install-config yaml file has been updated.${NC}"
echo -e "${CYAN} This lab is now ready for cluster deployment.${NC}"
echo -e "${CYAN} Use the following command to create the OpenShift cluster:${NC}"
echo ""

echo -e "${GREEN} ------------------------------------------------------------------------ ${NC}"
echo -e "${GREEN} openshift-install create cluster --dir "${INSTALL_DIR}" --log-level=info ${NC}"
echo -e "${GREEN} ------------------------------------------------------------------------ ${NC}"
echo ""

#Print Separator
echo ""
echo " ================================================================================== "
echo ""

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