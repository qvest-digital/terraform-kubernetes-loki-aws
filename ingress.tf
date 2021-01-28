resource "kubernetes_ingress" "loki" {
  metadata {
    name = "loki"
    namespace = "monitoring"

    annotations = {
      "ingress.kubernetes.io/auth-secret" = loki-auth
      "ingress.kubernetes.io/auth-type"   = basic
      "kubernetes.io/ingress.class"       = "nginx"
    }
  }

  spec {
    rule {
      host = var.loki_ingress_host

      http {
        path {
          path = "/"

          backend {
            service_name = "loki"
            service_port = "3100"
          }
        }
      }
    }
  }
}
