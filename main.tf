############################
## Namespaces
############################


resource "kubernetes_namespace" "apps" {
  metadata {
    name = "apps"
  }
}

############################
## n8n
############################

resource "kubernetes_deployment" "n8n" {
  metadata {
    name      = "n8n"
    namespace = kubernetes_namespace.apps.metadata[0].name
    labels    = { app = "n8n" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "n8n" }
    }

    template {
      metadata {
        labels = { app = "n8n" }
      }

      spec {
        enable_service_links = false

        container {
          name  = "n8n"
          image = "n8nio/n8n:latest"

          port {
            container_port = 5678
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          env {
            name  = "GENERIC_TIMEZONE"
            value = "Europe/Paris"
          }
          env {
            name  = "N8N_HOST"
            value = var.domain_n8n
          }
          env {
            name  = "WEBHOOK_URL"
            value = "http://${var.domain_n8n}/"
          }
          env {
            name  = "N8N_PROTOCOL"
            value = "http"
          }
          env {
            name  = "N8N_SECURE_COOKIE"
            value = "false"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "n8n" {
  metadata {
    name      = "n8n"
    namespace = kubernetes_namespace.apps.metadata[0].name
  }

  spec {
    selector = { app = "n8n" }

    port {
      port        = 5678
      target_port = 5678
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "n8n" {
  metadata {
    name      = "n8n"
    namespace = kubernetes_namespace.apps.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class" = "traefik"
    }
  }

  spec {
    rule {
      host = var.domain_n8n

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.n8n.metadata[0].name
              port {
                number = 5678
              }
            }
          }
        }
      }
    }
  }
}

############################
## Namespace monitoring
############################

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

############################
## Prometheus
############################

resource "kubernetes_config_map" "prometheus" {
  metadata {
    name      = "prometheus-config"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "prometheus.yml" = <<-EOT
      global:
        scrape_interval: 15s

      scrape_configs:
        - job_name: 'prometheus'
          static_configs:
            - targets: ['localhost:9090']

        - job_name: 'kubernetes-nodes'
          kubernetes_sd_configs:
            - role: node
          relabel_configs:
            - action: labelmap
              regex: __meta_kubernetes_node_label_(.*)

        - job_name: 'kubernetes-pods'
          kubernetes_sd_configs:
            - role: pod
          relabel_configs:
            - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
              action: keep
              regex: true
            - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
              action: replace
              target_label: __metrics_path__
              regex: (.+)
    EOT
  }
}

resource "kubernetes_cluster_role" "prometheus" {
  metadata {
    name = "prometheus"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "pods", "services", "endpoints"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get"]
  }
}

resource "kubernetes_service_account" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding" "prometheus" {
  metadata {
    name = "prometheus"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.prometheus.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.prometheus.metadata[0].name
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
}

resource "kubernetes_deployment" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels    = { app = "prometheus" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "prometheus" }
    }

    template {
      metadata {
        labels = { app = "prometheus" }
      }

      spec {
        service_account_name = kubernetes_service_account.prometheus.metadata[0].name

        container {
          name  = "prometheus"
          image = "prom/prometheus:v2.51.2"

          args = [
            "--config.file=/etc/prometheus/prometheus.yml",
            "--storage.tsdb.path=/prometheus",
            "--storage.tsdb.retention.time=15d",
          ]

          port {
            container_port = 9090
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/prometheus"
          }

          volume_mount {
            name       = "data"
            mount_path = "/prometheus"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.prometheus.metadata[0].name
          }
        }

        volume {
          name = "data"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  spec {
    selector = { app = "prometheus" }

    port {
      port        = 9090
      target_port = 9090
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class" = "traefik"
    }
  }

  spec {
    rule {
      host = var.domain_prometheus

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.prometheus.metadata[0].name
              port { number = 9090 }
            }
          }
        }
      }
    }
  }
}

############################
## Grafana
############################

resource "kubernetes_config_map" "grafana" {
  metadata {
    name      = "grafana-datasources"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "datasources.yaml" = <<-EOT
      apiVersion: 1
      datasources:
        - name: Prometheus
          type: prometheus
          url: http://prometheus:9090
          isDefault: true
    EOT
  }
}

resource "kubernetes_deployment" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels    = { app = "grafana" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "grafana" }
    }

    template {
      metadata {
        labels = { app = "grafana" }
      }

      spec {
        container {
          name  = "grafana"
          image = "grafana/grafana:10.4.2"

          port {
            container_port = 3000
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          env {
            name  = "GF_SECURITY_ADMIN_USER"
            value = "admin"
          }
          env {
            name  = "GF_SECURITY_ADMIN_PASSWORD"
            value = "admin"
          }
          env {
            name  = "GF_AUTH_ANONYMOUS_ENABLED"
            value = "false"
          }
          env {
            name  = "GF_SERVER_DOMAIN"
            value = var.domain_grafana
          }
          env {
            name  = "GF_SERVER_ROOT_URL"
            value = "http://$${GF_SERVER_DOMAIN}"
          }

          volume_mount {
            name       = "datasources"
            mount_path = "/etc/grafana/provisioning/datasources"
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/grafana"
          }
        }

        volume {
          name = "datasources"
          config_map {
            name = kubernetes_config_map.grafana.metadata[0].name
          }
        }

        volume {
          name = "data"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  spec {
    selector = { app = "grafana" }

    port {
      port        = 3000
      target_port = 3000
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class" = "traefik"
    }
  }

  spec {
    rule {
      host = var.domain_grafana

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.grafana.metadata[0].name
              port { number = 3000 }
            }
          }
        }
      }
    }
  }
}



############################
## Namespace prod
############################

resource "kubernetes_namespace" "prod" {
  metadata {
    name = "prod"
  }
}

############################
## Graylog
############################

resource "kubernetes_pod" "mongodb" {
  metadata {
    name      = "mongodb"
    namespace = kubernetes_namespace.prod.metadata[0].name
    labels = {
      app = "mongodb"
    }
  }

  spec {
    container {
      name  = "mongodb"
      image = "mongo:6.0"

      port {
        container_port = 27017
      }

      volume_mount {
        name       = "mongodb-data"
        mount_path = "/data/db"
      }
    }

    volume {
      name = "mongodb-data"
      empty_dir {}
    }
  }
}

resource "kubernetes_service" "mongodb" {
  metadata {
    name      = "mongodb"
    namespace = kubernetes_namespace.prod.metadata[0].name
  }

  spec {
    selector = {
      app = "mongodb"
    }

    port {
      port        = 27017
      target_port = 27017
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_pod" "opensearch" {
  metadata {
    name      = "opensearch"
    namespace = kubernetes_namespace.prod.metadata[0].name
    labels = {
      app = "opensearch"
    }
  }

  spec {
    container {
      name  = "opensearch"
      image = "opensearchproject/opensearch:2.11.0"

      port {
        container_port = 9200
      }

      port {
        container_port = 9300
      }

      env {
        name  = "discovery.type"
        value = "single-node"
      }

      env {
        name  = "DISABLE_SECURITY_PLUGIN"
        value = "true"
      }

      env {
        name  = "OPENSEARCH_JAVA_OPTS"
        value = "-Xms512m -Xmx512m"
      }

      volume_mount {
        name       = "opensearch-data"
        mount_path = "/usr/share/opensearch/data"
      }
    }

    volume {
      name = "opensearch-data"
      empty_dir {}
    }
  }
}

resource "kubernetes_service" "opensearch" {
  metadata {
    name      = "opensearch"
    namespace = kubernetes_namespace.prod.metadata[0].name
  }

  spec {
    selector = {
      app = "opensearch"
    }

    port {
      name        = "http"
      port        = 9200
      target_port = 9200
    }

    port {
      name        = "transport"
      port        = 9300
      target_port = 9300
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_config_map" "graylog" {
  metadata {
    name      = "graylog-config"
    namespace = kubernetes_namespace.prod.metadata[0].name
  }

  data = {
    "graylog.conf" = <<-EOT
      mongodb_uri = mongodb://mongodb.prod.svc.cluster.local:27017/graylog
      elasticsearch_hosts = http://opensearch.prod.svc.cluster.local:9200
      http_bind_address = 0.0.0.0:9000
      http_external_uri = http://72.61.107.65:30900/
      root_timezone = Europe/Paris
    EOT
  }
}

resource "kubernetes_pod" "graylog" {
  metadata {
    name      = "graylog"
    namespace = kubernetes_namespace.prod.metadata[0].name
    labels = {
      app = "graylog"
    }
  }

  spec {
    container {
      name  = "graylog"
      image = "graylog/graylog:5.1"

      port {
        container_port = 9000
      }

      port {
        container_port = 12201
        protocol       = "UDP"
      }

      port {
        container_port = 5514
        protocol       = "TCP"
      }

      env {
        name  = "GRAYLOG_PASSWORD_SECRET"
        value = "somepasswordpepper1234567890abc"
      }

      env {
        name  = "GRAYLOG_ROOT_PASSWORD_SHA2"
        value = "8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918"
      }

      env {
        name  = "GRAYLOG_HTTP_EXTERNAL_URI"
        value = "http://72.61.107.65:30900/"
      }

      env {
        name  = "GRAYLOG_MONGODB_URI"
        value = "mongodb://mongodb.prod.svc.cluster.local:27017/graylog"
      }

      env {
        name  = "GRAYLOG_ELASTICSEARCH_HOSTS"
        value = "http://opensearch.prod.svc.cluster.local:9200"
      }

      volume_mount {
        name       = "graylog-config"
        mount_path = "/usr/share/graylog/data/config/graylog.conf"
        sub_path   = "graylog.conf"
        read_only  = true
      }

      volume_mount {
        name       = "graylog-server-dir"
        mount_path = "/etc/graylog/server"
      }
    }

    volume {
      name = "graylog-server-dir"
      empty_dir {}
    }

    volume {
      name = "graylog-config"
      config_map {
        name = kubernetes_config_map.graylog.metadata[0].name
      }
    }
  }
}

resource "kubernetes_service" "graylog" {
  metadata {
    name      = "graylog"
    namespace = kubernetes_namespace.prod.metadata[0].name
  }

  spec {
    selector = {
      app = "graylog"
    }

    port {
      name        = "web"
      port        = 9000
      target_port = 9000
      node_port   = 30900
    }

    port {
      name        = "syslog-tcp"
      port        = 5514
      target_port = 5514
      node_port   = 30514
      protocol    = "TCP"
    }

    type = "NodePort"
  }
}


############################
## Nextcloud
############################

resource "kubernetes_pod" "nextcloud" {
  metadata {
    name      = "nextcloud"
    namespace = kubernetes_namespace.prod.metadata[0].name
    labels = {
      app = "nextcloud"
    }
  }

  spec {
    container {
      name  = "nextcloud"
      image = "nextcloud:latest"

      port {
        container_port = 80
      }

      env {
        name  = "NEXTCLOUD_ADMIN_USER"
        value = "admin"
      }

      env {
        name  = "NEXTCLOUD_ADMIN_PASSWORD"
        value = "admin"
      }

      env {
        name  = "NEXTCLOUD_TRUSTED_DOMAINS"
        value = "72.61.107.65"
      }

      volume_mount {
        name       = "nextcloud-data"
        mount_path = "/var/www/html"
      }

      volume_mount {
        name       = "nextcloud-logs"
        mount_path = "/var/log/nextcloud"
      }
    }

    container {
      name  = "log-sidecar"
      image = "busybox"

      command = [
        "sh",
        "-c",
        "until [ -f /logs/nextcloud.log ]; do sleep 1; done; tail -n+1 -F /logs/nextcloud.log | while IFS= read -r line; do [ -n \"$line\" ] && echo \"$line\" | tr -d '\\000-\\011\\013\\014\\016-\\037\\\\' | nc -w1 graylog.prod.svc.cluster.local 5514; done"
]

      volume_mount {
        name       = "nextcloud-data"
        mount_path = "/logs"
        sub_path   = "data"
      }
    }

    volume {
      name = "nextcloud-data"
      empty_dir {}
    }

    volume {
      name = "nextcloud-logs"
      empty_dir {}
    }
  }
}

resource "kubernetes_service" "nextcloud" {
  metadata {
    name      = "nextcloud"
    namespace = kubernetes_namespace.prod.metadata[0].name
  }

  spec {
    selector = {
      app = "nextcloud"
    }

    port {
      port        = 80
      target_port = 80
      node_port   = 30080
    }

    type = "NodePort"
  }
}

############################
## MinIO
############################

resource "kubernetes_deployment" "minio" {
  metadata {
    name      = "minio"
    namespace = kubernetes_namespace.prod.metadata[0].name
    labels    = { app = "minio" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "minio" }
    }

    template {
      metadata {
        labels = { app = "minio" }
      }

      spec {
        container {
          name  = "minio"
          image = "minio/minio:latest"

          args = ["server", "/data", "--console-address", ":9001"]

          port {
            container_port = 9000
          }

          port {
            container_port = 9001
          }

          env {
            name  = "MINIO_ROOT_USER"
            value = "minioadmin"
          }

          env {
            name  = "MINIO_ROOT_PASSWORD"
            value = "minioadmin"
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }

        volume {
          name = "data"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service" "minio" {
  metadata {
    name      = "minio"
    namespace = kubernetes_namespace.prod.metadata[0].name
  }

  spec {
    selector = { app = "minio" }

    port {
      name        = "api"
      port        = 9000
      target_port = 9000
    }

    port {
      name        = "console"
      port        = 9001
      target_port = 9001
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "minio" {
  metadata {
    name      = "minio"
    namespace = kubernetes_namespace.prod.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class" = "traefik"
    }
  }

  spec {
    rule {
      host = var.domain_minio

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.minio.metadata[0].name
              port {
                number = 9001
              }
            }
          }
        }
      }
    }
  }
}

############################
## Portainer
############################

resource "kubernetes_service_account" "portainer" {
  metadata {
    name      = "portainer"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding" "portainer" {
  metadata {
    name = "portainer"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.portainer.metadata[0].name
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
}

resource "kubernetes_deployment" "portainer" {
  metadata {
    name      = "portainer"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels    = { app = "portainer" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "portainer" }
    }

    template {
      metadata {
        labels = { app = "portainer" }
      }

      spec {
        service_account_name = kubernetes_service_account.portainer.metadata[0].name

        container {
          name  = "portainer"
          image = "portainer/portainer-ce:latest"

          args = ["--http-enabled"]

          port {
            container_port = 9000
          }

          port {
            container_port = 9443
          }

          port {
            container_port = 8000
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }

        volume {
          name = "data"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service" "portainer" {
  metadata {
    name      = "portainer"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  spec {
    selector = { app = "portainer" }

    port {
      name        = "http"
      port        = 9000
      target_port = 9000
    }

    port {
      name        = "edge"
      port        = 8000
      target_port = 8000
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "portainer" {
  metadata {
    name      = "portainer"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class" = "traefik"
    }
  }

  spec {
    rule {
      host = var.domain_portainer

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.portainer.metadata[0].name
              port {
                number = 9000
              }
            }
          }
        }
      }
    }
  }
}

############################
## HPA
############################

resource "kubernetes_horizontal_pod_autoscaler_v2" "n8n" {
  metadata {
    name      = "n8n"
    namespace = kubernetes_namespace.apps.metadata[0].name
  }

  spec {
    min_replicas = 1
    max_replicas = 3

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.n8n.metadata[0].name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  spec {
    min_replicas = 1
    max_replicas = 3

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.grafana.metadata[0].name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}