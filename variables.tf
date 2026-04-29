variable "kubeconfig_path" {
  description = "Chemin vers le fichier kubeconfig K3s"
  type        = string
  default     = "/home/john/.kube/config"
}

variable "domain_n8n" {
  description = "Domaine pour accéder à n8n (ex: n8n.local)"
  type        = string
  default     = "n8n.local"
}

variable "domain_prometheus" {
  description = "Domaine pour accéder à Prometheus"
  type        = string
  default     = "prometheus.local"
}

variable "domain_grafana" {
  description = "Domaine pour accéder à Grafana"
  type        = string
  default     = "grafana.local"
}

variable "domain_portainer" {
  description = "Domaine pour accéder à Portainer"
  type        = string
  default     = "portainer.local"
}

variable "domain_minio" {
  description = "Domaine pour accéder à la console MinIO"
  type        = string
  default     = "minio.local"
}


