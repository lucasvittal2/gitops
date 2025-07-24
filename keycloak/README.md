# 🚀 Keycloak Deployment on Kubernetes with Minikube

This repository provides artifacts and scripts to deploy Keycloak on Kubernetes using Minikube for **dev**, **homolog** and **production** environments. The deployment is streamlined with a Bash script to simplify setup and configuration.

---

## 📁 Directory Structure

```txt
keycloak/
├── homolog/
│   ├── keycloak.yaml           # Keycloak deployment manifest for homolog environment
│   └── keycloak-ingress_template.yaml  # Ingress template for homolog environment
├── production/
│   ├── keycloak.yaml           # Keycloak deployment manifest for production environment
│   └── keycloak-ingress.yaml   # Ingress configuration for production environment
└── deploy.sh                   # Bash script to automate deployment
```

---

## 📋 Pre-requisites

To deploy Keycloak using this repository, ensure you have the following tools installed:

- **[Minikube](https://minikube.sigs.k8s.io/docs/)**: A tool to run a single-node Kubernetes cluster locally.
- **[kubectl](https://kubernetes.io/docs/tasks/tools/)**: The Kubernetes command-line tool for interacting with the cluster.
- **Bash shell**: Available on Linux or macOS. For Windows, use WSL2 or Git Bash.
- **Docker**: Required by Minikube to run containers (ensure Docker is running before starting Minikube).
- **kubectl ingress-nginx**: Optional, for enabling Ingress support (required for accessing Keycloak via a browser).

---

## 🧪 Supported Environments

This repository supports two environments:
- **homolog**: A testing environment developing and testing
- **homolog**: A testing environment for validation and make app available for external squads testing it.
- **production**: A stable environment with production-ready configurations to be used by clients.

---

## 🚀 Deployment Instructions

Follow these steps to deploy Keycloak on Minikube:

### 1. Start Minikube
Ensure Minikube is running with the necessary add-ons:
```bash
minikube start --driver=docker
minikube addons enable ingress
```

### 2. Deploy Keycloak
Use the provided `deploy.sh` script to deploy Keycloak to the desired environment:
```bash
./keycloak/deploy.sh --env <ENVIRONMENT>
```
Replace `<ENVIRONMENT>` with either `homolog` or `production`.

Example:
```bash
./keycloak/deploy.sh --env dev
```

### 3. Access Keycloak
when deployment finished you will se the main link to acess keycloak interface:
```txt
KEYCLOAK DEPLOYMENT SUCCESSFUL - homolog ENVIRONMENT
**********************************************************************
Keycloak:                 https://keycloak.<HOST_ADDRESS>.nip.io
Keycloak Admin Console:   https://keycloak.<HOST_ADDRESS>.nip.io/admin
Keycloak Account Console: https://keycloak.<HOST_ADDRESS>.nip.io/realms/myrealm/account
```

just click in one of them to acess the desired interface
---

## 🔍 Verifying the Deployment

To confirm Keycloak is running:
```bash
kubectl get pods -n keycloak
kubectl get ingress -n keycloak
```

Ensure the Keycloak pod is in the `Running` state and the ingress is correctly configured.

---

## 🛠️ Troubleshooting

- **Minikube not starting**: Ensure Docker is running and you have sufficient resources (CPU, memory).
- **Ingress not working**: Verify the `ingress` add-on is enabled (`minikube addons list`) and your `/etc/hosts` file is updated with the correct Minikube IP.
- **Pod crashes**: Check logs with `kubectl logs <pod-name> -n keycloak` to diagnose issues.
- **Environment not found**: Ensure the `--env` flag is set to either `homolog` or `production`.

---

## 📝 Notes

- The `homolog` environment uses a template for the ingress, which may require customization based on your setup.
- The `production` environment is optimized for stability and may include additional configurations like resource limits and scaling options.
- Always stop Minikube when done to free up resources:
  ```bash
  minikube stop
  ```