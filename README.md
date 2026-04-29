# Projet Kubernetes / Terraform

Déploiement automatisé d'une stack complète sur un cluster K3d multi-nœud via Terraform et GitHub Actions.

---

## Architecture

```
GitHub Actions (CI/CD)
        │
        ▼
   Terraform (IaC)
        │
        ▼
  Cluster K3d (72.60.206.107)
  ├── k3d-mycluster-server-0  (control-plane)
  ├── k3d-mycluster-agent-0   (worker)
  │
  ├── Namespace apps
  │   └── n8n
  ├── Namespace monitoring
  │   ├── Prometheus
  │   ├── Grafana
  │   └── Portainer
  └── Namespace prod
      ├── Graylog
      ├── OpenSearch
      ├── MongoDB
      └── Nextcloud (+ sidecar logs)
```

---

## Services déployés

| Namespace | Service | Rôle |
|---|---|---|
| `apps` | n8n | Automatisation de workflows |
| `monitoring` | Prometheus | Collecte de métriques |
| `monitoring` | Grafana | Visualisation des métriques |
| `monitoring` | Portainer | Dashboard de gestion du cluster |
| `prod` | Graylog | Agrégation et visualisation des logs |
| `prod` | OpenSearch | Moteur d'indexation pour Graylog |
| `prod` | MongoDB | Base de données pour Graylog |
| `prod` | Nextcloud | Stockage de fichiers en ligne |
| `prod` | MinIO | Stockage objet S3-compatible |

---

## Infrastructure as Code (Terraform)

Tous les workloads sont décrits en Terraform (`main.tf`) :

- **Namespaces** : `apps`, `monitoring`, `prod`
- **Deployments / Pods** : un par service
- **Services** : ClusterIP pour les services internes, NodePort pour Graylog et Nextcloud
- **Ingress Traefik** : n8n, Prometheus, Grafana, Portainer
- **RBAC** : ServiceAccount + ClusterRoleBinding pour Prometheus et Portainer
- **ConfigMaps** : configuration de Prometheus et Graylog
- **Sidecar** : container `busybox` dans le pod Nextcloud qui forward les logs vers Graylog en TCP (port 5514)

Fichiers :

```
main.tf           # Ressources Kubernetes
providers.tf      # Providers Terraform (kubernetes ~> 2.28)
variables.tf      # Variables (domaines, kubeconfig)
terraform.tfvars  # Valeurs des variables
```

---

## Pipeline CI/CD

Fichier : `.github/workflows/deploy.yml`

**Déclencheur** : push sur la branche `main`

**Étapes** :
1. Checkout du dépôt
2. Installation de Terraform
3. Écriture du kubeconfig depuis le secret GitHub `KUBECONFIG`
4. `terraform init`
5. `terraform apply -auto-approve`

Le secret `KUBECONFIG` contient le fichier kubeconfig du cluster K3s encodé en base64, avec l'IP publique du serveur (`72.60.206.107`).

---

## Supervision

- **Prometheus** scrape les nœuds et pods du cluster toutes les 15 secondes
- **Grafana** est connecté à Prometheus comme datasource par défaut
- **Portainer** permet de visualiser et gérer les ressources Kubernetes via une interface web
- **Graylog** agrège les logs applicatifs — Nextcloud envoie ses logs en temps réel via un sidecar

---

## Prérequis

- Cluster K3d opérationnel (1 serveur + 1 agent)
- Secret GitHub `KUBECONFIG` configuré (Settings → Secrets and variables → Actions)
- Terraform >= 1.5.0

> **Note** : le cluster multi-nœud est simulé via K3d (K3s dans Docker) sur un seul VPS faute de ressources pour un second serveur physique. Le cluster expose bien 2 nœuds distincts (`control-plane` + `worker`).

---

## Responsabilités

### Baptiste Bellanger
- Mise en place de l'Infrastructure as Code (Terraform) — `providers.tf`, `variables.tf`, `main.tf`
- Déploiement du namespace `monitoring` : Prometheus + Grafana avec RBAC et datasource provisionnée
- Configuration de la pipeline CI/CD GitHub Actions
- Configuration du secret `KUBECONFIG` et accès au cluster depuis GitHub

### Arnaud Preci
- Déploiement du namespace `apps` : n8n (deployment, service, ingress)
- Déploiement du namespace `prod` : Graylog, OpenSearch, MongoDB, Nextcloud
- Mise en place du sidecar de logs (Nextcloud → Graylog via TCP 5514)
- Déploiement du dashboard Portainer avec ServiceAccount et ClusterRoleBinding
- Déploiement de MinIO (stockage objet S3-compatible) et intégration comme stockage externe Nextcloud
