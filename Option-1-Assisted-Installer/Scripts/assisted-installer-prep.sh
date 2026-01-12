#!/usr/bin/env bash

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
# Print Staring Script Message
#-------------------------------------------------------------

echo -e "${RED}"
echo "  --------------------------------------------------------------------------------  "
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
echo " --- Starting the Assisted Installer Preparation automation script..."
echo -e "${NC}"

echo " ================================================================================== "
echo ""

#===================================================================================

#-------------------------------------------------------------
# Collect and Confirm User Inputs For Lab Environement Info
#-------------------------------------------------------------

echo -e "${YELLOW} Collect & Confirm Lab Environement Info${NC}"
echo -e "${YELLOW} ---------------------------------------${NC}"
echo ""

while true; do
  echo -e "${YELLOW} - Please provide the required lab environement info below:${NC}"
  echo -e "${BLUE}     - VMware vCenter Server Info:${NC}"
  read -rp "       Enter vCenter URL (e.g. vc.example.com): " VCENTER_URL
  read -rp "       Enter vCenter username: " VCENTER_USERNAME
  read -rsp "       Enter vCenter password: " VCENTER_PASSWORD
  echo ""

  echo -e "${BLUE}     - Red Hat OpenShift Cluster Info:${NC}"
  read -rp "       Enter OpenShift release (e.g. 4.20.4): " OCP_RELEASE
  echo ""

  echo -e "${BLUE}     - Lab Environement Info:${NC}"
  read -rp "       Enter lab base domain (e.g. dynamic.example.com): " LAB_DOMAIN
  read -rp "       Enter lab ID (e.g. vrtzn): " LAB_ID
  echo ""

  echo -e "${YELLOW} - Please review the provided information below & confirm (Yy/Nn):${NC}"
  echo "   ----------------------------------------"
  echo "   vCenter URL       : $VCENTER_URL"
  echo "   vCenter Username  : $VCENTER_USERNAME"
  echo "   vCenter Password  : ********"
  echo "   OpenShift Release : $OCP_RELEASE"
  echo "   Lab Base Domain   : $LAB_DOMAIN"
  echo "   Lab ID            : $LAB_ID"
  echo "   ----------------------------------------"
  echo ""

  # --- Confirmation loop (Y/N only) ---
  while true; do
    read -rp "   Are the above provided informations correct? (Y/N): " CONFIRM

    case "$CONFIRM" in
      [Yy])
        echo -e "${GREEN}   Input confirmed. Proceeding...${NC}"
        CONFIRMED=true
        break
        ;;
      [Nn])
        echo -e "${YELLOW}   Re-entering input details...${NC}"
        echo ""
        CONFIRMED=false
        break
        ;;
      *)
        echo -e "${RED}   Invalid input. Please enter Y or N only.${NC}"
        ;;
    esac
  done

  [[ "$CONFIRMED" == "true" ]] && break
done

# Export govc environment variables
export GOVC_URL=$VCENTER_URL
export GOVC_USERNAME=$VCENTER_USERNAME
export GOVC_PASSWORD=$VCENTER_PASSWORD
export GOVC_INSECURE=1

#----------------------------------------------------------------------------------
# Section Environment Outputs
#
# This section captures the required lab and vCenter details and exports them as
# environment variables for use by govc and OpenShift preparation tasks.
#
# Variables set by this section:
# - LAB_ID          : Unique identifier for the lab
# - LAB_DOMAIN      : Base domain for the lab environment
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
  echo ""

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

  while true; do
    read -rp "   Is this correct? (Y/N): " CONFIRM
    case "$CONFIRM" in
      [Yy]) echo -e "${GREEN}   Cluster selection confirmed. Proceeding...${NC}"; break 2 ;;
      [Nn]) echo -e "${YELLOW}   Re-entering cluster selection...${NC}"; break ;;
      *)    echo -e "${RED}   Invalid input. Please enter Y or N only.${NC}" ;;
    esac
  done
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

#------------------------------------------------------------------------

echo -e "${YELLOW} Check The Required Node(s) HW Resources${NC}"
echo -e "${YELLOW} ---------------------------------------${NC}"
echo ""

# ----------------------------
# Check if COMPACT CLUSTER - then provide the defaults and ask for confirmation or gather user required inputs
# ----------------------------
if [[ "$CLUSTER_MODE" == "compact" ]]; then
  # Defaults
  MASTER_CPU=12; MASTER_RAM_GB=32; MASTER_DISK_GB=250

  # Thresholds
  CPU_MIN=12; CPU_MAX=16; RAM_MIN=24; RAM_MAX=48; DISK_MIN=120; DISK_MAX=250


  echo ""
  echo -e "${YELLOW} - Selected OpenShift Cluster Type is 3-node Compact Cluster.${NC}"
  echo -e "${YELLOW} - Below are the default node HW resources:${NC}"
  echo "   ---------------------------"
  echo "   vCPU   : $MASTER_CPU"
  echo "   RAM    : $MASTER_RAM_GB GB"
  echo "   Disk   : $MASTER_DISK_GB GB"
  echo "   ---------------------------"
  echo ""

  if confirm_yn "   Proceed with these default values (Yy/Nn)?"; then
    echo -e "${GREEN}   Using default VM sizing. Proceeding...${NC}"
  else
    while true; do
      echo -e "${BLUE}   Enter custom VM sizing for compact nodes:${NC}"

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

      if confirm_yn "   Proceed with this VM sizing (Yy/Nn)?"; then
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
# Check if STANDARD CLUSTER - then provide the defaults and ask for confirmation or gather user required inputs
# ----------------------------
else
  # Defaults
  MASTER_CPU=4; MASTER_RAM_GB=16; MASTER_DISK_GB=120
  WORKER_CPU=8; WORKER_RAM_GB=32; WORKER_DISK_GB=200

  # Thresholds - masters
  M_CPU_MIN=4;  M_CPU_MAX=8; M_RAM_MIN=12; M_RAM_MAX=24; M_DISK_MIN=120; M_DISK_MAX=200

  # Thresholds - workers
  W_CPU_MIN=8;  W_CPU_MAX=16; W_RAM_MIN=16; W_RAM_MAX=48; W_DISK_MIN=120; W_DISK_MAX=250

  echo ""
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


  if confirm_yn "   Proceed with these default values (Yy/Nn)?"; then
    echo -e "${GREEN}   Using default VM sizing. Proceeding...${NC}"
  else
    # --- Custom sizing for masters (with confirmation) ---
    while true; do
      echo -e "${BLUE}   Enter custom VM sizing for Master nodes:${NC}"

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

      if confirm_yn "   Proceed with this master sizing (Yy/Nn)?"; then
        echo -e "${GREEN}   Master VM sizing confirmed. Proceeding...${NC}"
        break
      fi

      echo -e "${YELLOW}   Re-entering master VM sizing...${NC}"
    done

    echo ""

    # --- Custom sizing for workers (with confirmation) ---
    while true; do
      echo -e "${BLUE}   Enter custom VM sizing for Worker nodes:${NC}"

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

      if confirm_yn "   Proceed with this worker sizing (Yy/Nn)?"; then
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

