# Option 1 - Dedicated DNS Records option

This section documents the preparation of a Red Hat OpenShift demo lab on VMware using dedicated DNS records for the OpenShift API and applications. It focuses on building a simple, clean, single-cluster environment optimized for demos and enablement scenarios.

---

If you are already familiar with this repository, you can proceed directly to the [Step-By-Step-Guide](#section-dedicated-step-by-step-guide) section

---

## Section Dedicated Repo Description

This repository section provides the required automation tools to prepare an existing VMware-based lab environment that exposes two dedicated external DNS records—one for the OpenShift API endpoint and one for OpenShift applications. The purpose of this option is to simplify and standardize the deployment of a single Red Hat OpenShift cluster on top of VMware infrastructure.

Because this option relies on only two DNS records (API and Apps), it can support only one OpenShift cluster at a time. This limitation is inherent to the DNS design and is the primary reason this option is intentionally scoped for single-cluster deployments. As a result, this option is ideal for demo environments, enablement labs, and simple proof-of-concept setups where multi-cluster support is not required.

This option supports two OpenShift deployment methods:
- Assisted Installer, using the Red Hat Hybrid Cloud Console
- IPI (Installer-Provisioned Infrastructure)

Each deployment method has its own dedicated automation scripts, while sharing the same underlying DNS and VMware infrastructure assumptions.

In this model, the bastion host is used strictly as an automation and access node. It does not provide DNS, load balancing, or any infrastructure services for the OpenShift cluster. All DNS resolution and traffic routing are handled externally, which keeps the lab preparation lightweight and minimizes bastion host configuration.

**What This Option Automates**

- **For the Assisted Installer Option:**
  - A dedicated interactive Bash script is used to collect environment-specific inputs from the user and then automate the full preparation process. Based on the provided inputs, the automation performs the following actions:
    - Installs the required tools on the bastion host (for example: govc)
    - Downloads the Assisted Installer ISO
    - Uploads the ISO to the VMware datastore
    - Creates the required number of virtual machines based on user input
    - Applies the requested hardware configuration to each VM
    - Attaches the Assisted Installer ISO to the created virtual machines
    - Powers on the virtual machines to make them ready for discovery in the Assisted Installer UI
  - After the OpenShift cluster is successfully deployed, an additional post-installation script is provided to automatically:
    - Create an OpenShift admin user
    - Install and configure LVM on the cluster
  - An optional cleanup script is also included to stop and delete all created virtual machines, allowing the environment to be reset and reused easily.

- **For the IPI Installer Option:**
  - To Be Determined 

---

## Section Dedicated Understand The Infrastructure


![Dedicated-DNS-Arch-Diagram](/Option-1-Dedicated-DNS/images/Dedicated-DNS-Arch-Diagram.png)

In this DNS model, the VMware lab environment is designed so that external DNS fully owns name resolution for the OpenShift cluster. Two DNS records are created outside the lab environment: one for the OpenShift API endpoint and one wildcard record for OpenShift applications. These records are NATed to internal IP addresses within the NSX segment where the OpenShift nodes are deployed.

Traffic from external clients reaches the OpenShift cluster through the router, which performs NAT and forwards traffic directly to the appropriate internal IPs. Because DNS and traffic routing are handled externally, there is no need to run DNS services or load balancers inside the lab.

The bastion host exists on the same NSX segment as the OpenShift nodes and serves as the single entry point for administrators. Its role is limited to automation execution, SSH access, and interaction with VMware APIs. It does not participate in cluster traffic and does not sit in the data path between users and the OpenShift cluster.

The OpenShift cluster itself runs on virtual machines deployed across one or more ESXi hosts, backed by shared datastores. From the cluster’s perspective, networking behaves as if it were deployed in a traditional enterprise environment with externally managed DNS and ingress traffic, making this setup very close to real-world production designs while remaining simple to operate for demos.

---

## Section Dedicated Step-By-Step Guide

This section provides the primary step-by-step instructions for using this repository to prepare the demo lab environment using the Dedicated DNS Records option.

This option includes two deployment sub-options based on the OpenShift installation method: Assisted Installer and IPI. For an overview of this option, please refer to the [Dedicated DNS Records section](/Option-2-Wildcard-DNS/README.md)

### Assisted Installer Option

> This option prepares the lab environment for deploying Red Hat OpenShift using the Assisted Installer with two dedicated DNS records—one for the OpenShift API and one for applications.

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

**Step 5:** Run the post-installation configuration script

Once the OpenShift cluster is deployed and confirmed to be up and running, execute the post-installation configuration script. Before executing the post-installation script, some preparation are required. 

```bash
mkdir -p ~/.kube
chmod 700 ~/.kube
vim ~/.kube/config
```

Copy kubeconfig content to the above created file

```bash
chmod 600 ~/.kube/config
```

Execute the post-installation configuration script

```bash
./RH-Demo-OCP-On-VM-Preparation/Option-1-Dedicated-DNS/Scripts/Assisted-Installer/post-install-config.sh
```

**Step 6:** [Optional] - Clean up and delete deployed virtual machines

If you need to start over and remove the deployed virtual machines, run the cleanup script:

```bash
./RH-Demo-OCP-On-VM-Preparation/Option-1-Dedicated-DNS/Scripts/Assisted-Installer/stop-delete-vms.sh
```

---

### IPI Installer Option

TBC