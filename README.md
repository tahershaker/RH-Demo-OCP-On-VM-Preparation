# Red Hat OCP Demo Lab Preparation - VMware-Based Infrastructure

A repository providing automation tools (scripts, Ansible, and related assets) to prepare an existing VMware environment for deploying Red Hat OpenShift cluster(s) for demo and enablement use cases.

---

If you are already familiar with this repository, you can proceed directly to the [Step-By-Step-Guide](#step-by-step-guide) section

---

## Repo Description

This repository is dedicated to preparing demo and enablement lab environments for Red Hat OpenShift on top of VMware infrastructure. It provides step-by-step guides, scripts, Ansible playbooks and roles, configuration files, and supporting tools to automate the repetitive tasks required to build a functional OpenShift demo lab.

The lab is prepared using a bastion host and is designed to support multiple OpenShift installation methods, while remaining repeatable, consistent, and easy to rebuild for demonstrations and learning purposes.

---

## Repo Content

This repository automates the preparation of an existing VMware-based lab environment for deploying Red Hat OpenShift cluster(s). The prepared lab can support different OpenShift installation methods and cluster architectures - depending on how DNS is provided in the environment - making it suitable for demo, enablement, and learning scenarios.

This repository assumes a pre-installed VMware lab environment with the following components:
- A vSphere virtual datacenter with a cluster sized to meet the compute requirements of the OpenShift cluster(s).
- One or more datastores attached to the ESXi hosts.
- An NSX segment providing DHCP, internal VM connectivity, and outbound internet access.
- A bastion host connected to the NSX segment and used as the automation and access point.
- External DNS configured using one of the following two models.
  - Two DNS records (one for the OpenShift API and one for applications), NATed to internal IP addresses within the lab.
  - A single wildcard DNS record pointing to the bastion host.

This repository focuses on preparing the lab environment for Red Hat OpenShift deployment. While the goal is OpenShift installation, the content is structured based on the DNS options available in the lab environment, as DNS design directly impacts the required bastion host preparation, deployment workflow, and the number of OpenShift clusters that can be supported.

Accordingly, this repository provides two preparation options: a **Dedicated DNS Records option** and a **Wildcard DNS Record option**. Both Assisted Installer and IPI (Installer-Provisioned Infrastructure) can be used with either DNS option.

**Dedicated DNS Records option**

- This option prepares the lab environment for deploying a single Red Hat OpenShift cluster using dedicated DNS records for the OpenShift API and applications. It supports both Assisted Installer and IPI (Installer-Provisioned Infrastructure) installation methods.
- This option provides scripts that automate the installation, deployment, and configuration of the required tools and resources to simplify the OpenShift cluster deployment workflow.
- All automation tasks for this option are executed from the bastion host and focus on preparing the VMware environment by installing required tools (such as GOVC) and automating repeatable tasks such as virtual machine creation. The user must clone this Git repository on the bastion host and then execute the required automation tools.
- This option supports deploying either a compact cluster (3 nodes acting as both control plane and workers) or a standard cluster with 3 control plane nodes and a configurable number of worker nodes. No DNS or HAProxy configuration is required on the bastion host.
- For more details, refer to the [Dedicated DNS Option section](/Option-1-Dedicated-DNS/README.md) in this repository.

**Wildcard DNS Record Option**

- This option prepares the lab environment for deploying one or more Red Hat OpenShift clusters using a single wildcard DNS record pointing to the bastion host. It supports both Assisted Installer and IPI (Installer-Provisioned Infrastructure) installation methods and allows deploying compact or standard OpenShift cluster architectures.
- This option provides scripts that automate the installation, deployment, and configuration of the required tools, resources and infrastructure components to simplify the OpenShift cluster(s) deployment workflow.
- All automation tasks in this option are executed from the bastion host, which is prepared to act as a central infrastructure node. This includes installing and configuring required software packages such as DNS and HAProxy, installing required tools (such as GOVC), and automating repeatable tasks like virtual machine creation and cluster networking preparation. The user must clone this Git repository on the bastion host and then execute the required automation tools.
- This option supports deploying either a compact cluster (3 nodes acting as both control plane and workers) or a standard cluster with 3 control plane nodes and a configurable number of worker nodes.
- For more details, refer to the [Wildcard DNS Option section](/Option-2-Wildcard-DNS/README.md) in this repository.

---

## Step-By-Step Guide

This section provides the primary step-by-step instructions for using this repository to prepare the demo lab environment.

> **Note:** This repository supports multiple deployment options and scenarios. Each subsection below is dedicated to a specific DNS option and OpenShift installation method.

### Option 1 - Dedicated DNS Records option

This option includes two deployment sub-options based on the OpenShift installation method: Assisted Installer and IPI. For an overview of this option, please refer to the [Dedicated DNS Records section](/Option-2-Wildcard-DNS/README.md)

#### [1] Assisted Installer Option - With Dedicated DNS Records

> This option prepares the lab environment for deploying Red Hat OpenShift using the Assisted Installer with two dedicated DNS records — one for the OpenShift API and one for applications.

**Step 1:** Prepare the required input information

The script prompts the user for several inputs required to perform the necessary actions. These values are provided interactively, one by one. Prepare the following information before running the script:

```bash
- vCenter URL:
- vCenter username:
- vCenter password:
- vSphere VM folder full path: 
- vSphere datastore name:
- vSphere network name:
- Required OpenShift release: 
- Assisted Installer ISO wget command:
```

**Step 2:** Clone the Git repository

```bash
git clone https://github.com/tahershaker/RH-Demo-OCP-On-VM-Preparation.git
```

**Step 3:** Make the Assisted Installer scripts executable

```bash
chmod +x RH-Demo-OCP-On-VM-Preparation/Option-1-Dedicated-DNS/Scripts/Assisted-Installer/*
```

**Step 4:** Run the Assisted Installer preparation script

```bash
./RH-Demo-OCP-On-VM-Preparation/Option-1-Dedicated-DNS/Scripts/Assisted-Installer/assisted-installer-prep.sh
```

**Step 5:** [Optional] Run the create-admin-user script

Once the OpenShift cluster is deployed and confirmed to be up and running, execute the create-admin-user script. Before executing the create-admin-user script, some preparation are required. 

```bash
mkdir -p ~/.kube
chmod 700 ~/.kube
vim ~/.kube/config
```

Copy kubeconfig content to the above created file

```bash
chmod 600 ~/.kube/config
```

Execute the create-admin-user script

```bash
./RH-Demo-OCP-On-VM-Preparation/Option-1-Dedicated-DNS/Scripts/Assisted-Installer/create-admin-user.sh
```

**Step 6:** [Optional] - Clean up and delete deployed virtual machines

If you need to start over and remove the deployed virtual machines, run the cleanup script:

```bash
./RH-Demo-OCP-On-VM-Preparation/Option-1-Dedicated-DNS/Scripts/Assisted-Installer/stop-delete-vms.sh
```

---

#### [2] IPI Installer Option - With Dedicated DNS Records

> This option prepares the lab environment for deploying Red Hat OpenShift using the IPI Installer with two dedicated DNS records — one for the OpenShift API and one for applications.

**Step 1:** Prepare the required input information

The script prompts the user for several inputs required to perform the necessary actions. These values are provided interactively, one by one. Prepare the following information before running the script:

```bash
- vCenter URL:
- vCenter username:
- vCenter password:
- vCenter Datacenter Name:
- vCenter Cluster Name:
- vCenter VM folder Name: 
- vCenter Datastore name:
- vCenter Network name:
- Required OpenShift release: 
- OpenShift API VIP IP:
- OpenShift Apps VIP IP:
- Lab Main Domain:
- Lab ID:
- Red Hat Pull Secret:
- User SSH Key:
```

**Step 2:** Clone the Git repository - Please Note: The repository must be cloned into the user’s home directory. The scripts rely on this specific path and will not work if the repository is located elsewhere.

```bash
git clone https://github.com/tahershaker/RH-Demo-OCP-On-VM-Preparation.git
```

**Step 3:** Make the IPI Installer scripts executable

```bash
chmod +x RH-Demo-OCP-On-VM-Preparation/Option-1-Dedicated-DNS/Scripts/IPI-Installer/*
```

**Step 4:** Run the IPI Installer preparation script

This script updates the `install-config` template based on the supplied information. After completion, the user is required to manually run the `openshift-install create` command to start the OpenShift cluster deployment. The script will output the exact command to use.

```bash
./RH-Demo-OCP-On-VM-Preparation/Option-1-Dedicated-DNS/Scripts/IPI-Installer/ipi-installer-prep.sh
```

Once the script completes, it will output the exact `openshift-install create` command required to deploy the OpenShift cluster. Copy and past the provided command in the terminal to start the OpenShift cluster deployment.

**Step 5:** [Optional] Run the create-admin-user script 

Once the IPI script completes, it outputs the `export KUBECONFIG` command required to access the cluster. The user must execute this command before running the next script.

Execute the create-admin-user script

```bash
./RH-Demo-OCP-On-VM-Preparation/Option-1-Dedicated-DNS/Scripts/IPI-Installer/create-admin-user.sh
```

---