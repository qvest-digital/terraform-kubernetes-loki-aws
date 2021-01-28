resource "kubernetes_ingress" "loki" {
  metadata {
    name = "loki"
    namespace = "monitoring"

    annotations = {
      "kubernetes.io/ingress.class"       = "nginx"
      "nginx.ingress.kubernetes.io/auth-secret" = "loki-auth"
      "nginx.ingress.kubernetes.io/auth-type"   = "basic"
      "nginx.ingress.kubernetes.io/auth-realm" = "Authentication Required"
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
