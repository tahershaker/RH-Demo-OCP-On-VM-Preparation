# Red Hat OCP Demo Lab Preparation - VMware-Based Infrastructure

A repository providing automation tools (scripts, Ansible, and related assets) to prepare an existing VMware environment for deploying Red Hat OpenShift cluster(s) for demo and enablement use cases.

---

If you are already familiar with this repository, you can proceed directly to the [Step-By-Step-Guide](#step-by-step-guide) section

---

## Repo Description

This repository is dedicated to demo environment preparation. Its primary purpose is to provide all required step-by-step guides, scripts, Ansible playbooks and roles, configuration files, and supporting tools needed to automate repetitive tasks involved in building a demo lab on top of VMware infrastructure.

The lab is prepared using a bastion host and is designed to support the deployment and management of Red Hat OpenShift for demo, enablement, and learning use cases. The focus is on creating a repeatable, consistent, and automation-driven environment that closely resembles real-world enterprise setups while remaining optimized for demonstrations rather than production workloads.

---

## Repo Content

This repository helps automate the preparation of an existing VMware-based lab environment for deploying Red Hat OpenShift cluster(s). The prepared lab can be used to support multiple OpenShift installation methods and cluster architectures, making it suitable for demo, enablement, and learning scenarios.

To provide additional context, this repository assumes the existence of a pre-installed and pre-configured VMware lab environment with the following components:
- A vSphere virtual datacenter with a cluster configured and sufficient ESXi capacity to meet the compute requirements of the OpenShift cluster(s).
- One or more datastores configured and attached to the ESXi hosts.
- An NSX segment that provides DHCP services, enables internal connectivity between virtual machines, and allows outbound internet access.
- A bastion host that provides SSH access to the internal lab network and is connected to the NSX segment.
- External DNS configured using one of the following approaches:
- Two DNS records (one for the OpenShift API and one for applications), NATed to internal IP addresses within the lab.
- A single wildcard DNS record pointing to the bastion host.

The repository supports two main preparation options, each aligned with a specific OpenShift installation method:

**Assisted Installer Option**

- This option prepares the lab environment for deploying Red Hat OpenShift using the Assisted Installer via the Red Hat Hybrid Cloud Console. It supports deploying a single OpenShift cluster, either as a 3-node compact cluster or a 6-node standard cluster.
- This option provides scripts that automate the installation, deployment, and configuration of required tools and resources to simplify the Assisted Installer workflow. The focus is on running automation from the bastion host, including installing required tools (such as govc) and automating repeatable tasks like virtual machine creation.
- For more details, refer to the [corresponding section](/Option-1-Assisted-Installer/README.md) in this repository.

**IPI Installer Option**

- This option prepares the lab environment for deploying Red Hat OpenShift using the UBI-based installation method. It supports greater flexibility, including single or multiple OpenShift clusters, as well as compact or standard cluster architectures.
- This option provides scripts to automate the installation, deployment, and configuration of required tools and infrastructure components. It focuses on using the bastion host as a central infrastructure node by installing required software packages (such as DNS and HAProxy), required tools (such as govc), and automating repeatable tasks like virtual machine creation.
- For more details, refer to the [corresponding section](/Option-2-UBI-Installer/README.md) in this repository.

---

## Step-By-Step Guide

This section serves as the primary step-by-step guide for using this repository and preparing the demo lab environment. 

> **Note:** This repository supports multiple deployment options and scenarios, with each subsection dedicated to a specific option or scenario.

### Option 1 - Assisted Installer Option

1- Prepare the required info for the script to run 

The script will ask the user for serverl info to be able to perofrm the required action. These info will be provided to the script as user inputs and the script will ask the user for each info one-by-one. Prepare these info to be able to use the provided script. Required info provided below

```bash
- vCenter URL:
- vCenter username:
- vCenter password:
- vSphere VM folder full path: 
- vSphere datastore name:
- vSphere network name:
- Required OpenShift release: 
- OpenShift Cluster Type: 
-       1) 3-node compact cluster (masters also act as workers)
-       2) Standard cluster (3 masters + x worker nodes)
- Required Node(s) HW Resources: - Script will provide defaults, user can change if required
- Assisted Installer ISO wget command:
-       Example: wget -O discovery_image_xxx.iso 'https://api.openshift.com/api/assisted-images/.../full.iso'
```

2- Clone the Git Repo

```bash
git clone https://github.com/tahershaker/RH-Demo-OCP-On-VM-Preparation.git
```

3- Change permissions for assisted-installer-prep.sh to be executable

```bash
chmod +x RH-Demo-OCP-On-VM-Preparation/Option-1-Assisted-Installer/Scripts/assisted-installer-prep.sh
```

4- Run Script

```bash
./RH-Demo-OCP-On-VM-Preparation/Option-1-Assisted-Installer/Scripts/assisted-installer-prep.sh
```

---

