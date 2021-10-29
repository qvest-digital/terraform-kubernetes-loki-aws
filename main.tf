locals {
  aws_iam_path_prefix = var.aws_iam_path_prefix == "" ? null : var.aws_iam_path_prefix
  aws_region_name     = data.aws_region.current.name
  k8s_namespace       = var.k8s_namespace
  k8s_pod_annotations = var.k8s_pod_annotations
  loki_docker_image   = "docker.io/grafana/loki:${var.loki_version}"
  loki_version        = var.loki_version
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# The EKS cluster (if any) that represents the installation target.
data "aws_eks_cluster" "selected" {
  count = var.k8s_cluster_type == "eks" ? 1 : 0
  name  = var.k8s_cluster_name
}

data "aws_iam_policy_document" "ec2_assume_role" {
  count = var.k8s_cluster_type == "vanilla" ? 1 : 0
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "eks_oidc_assume_role" {
  count = var.k8s_cluster_type == "eks" ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_eks_cluster.selected[0].identity[0].oidc[0].issuer, "https://", "")}:sub"
      values = [
        "system:serviceaccount:${var.k8s_namespace}:loki"
      ]
    }
    principals {
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.selected[0].identity[0].oidc[0].issuer, "https://", "")}"
      ]
      type = "Federated"
    }
  }
}

data "aws_iam_policy_document" "this" {
  statement {
    actions = [
      "s3:ListBucket",
      "s3:PutObject",
      "s3:GetObject"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.chunks.bucket}",
      "arn:aws:s3:::${aws_s3_bucket.chunks.bucket}/*"
    ]
  }
  statement {
    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:ListTagsOfResource",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
      "dynamodb:UpdateItem",
      "dynamodb:UpdateTable",
      "dynamodb:CreateTable",
      "dynamodb:DeleteTable"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:dynamodb:${local.aws_region_name}:${data.aws_caller_identity.current.account_id}:table/${var.aws_resource_name_prefix}${var.k8s_cluster_name}-loki-index-*"
    ]
  }
  statement {
    actions = [
      "dynamodb:ListTables"
    ]
    effect    = "Allow"
    resources = ["*"]
  }
  statement {
    actions = [
      "application-autoscaling:DescribeScalableTargets",
      "application-autoscaling:DescribeScalingPolicies",
      "application-autoscaling:RegisterScalableTarget",
      "application-autoscaling:DeregisterScalableTarget",
      "application-autoscaling:PutScalingPolicy",
      "application-autoscaling:DeleteScalingPolicy"
    ]
    effect    = "Allow"
    resources = ["*"]
  }
  statement {
    actions = [
      "iam:GetRole",
      "iam:PassRole"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_iam_role.this.name}"
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = "${var.aws_resource_name_prefix}${var.k8s_cluster_name}-loki"
  description = "Permissions that are required by Loki to manage logs."
  path        = local.aws_iam_path_prefix
  policy      = data.aws_iam_policy_document.this.json
}

resource "aws_iam_role" "this" {
  name        = "${var.aws_resource_name_prefix}${var.k8s_cluster_name}-loki"
  description = "Permissions required by Loki to do it's job."
  path        = local.aws_iam_path_prefix

  tags = var.aws_tags

  force_detach_policies = true

  assume_role_policy = var.k8s_cluster_type == "vanilla" ? data.aws_iam_policy_document.ec2_assume_role[0].json : data.aws_iam_policy_document.eks_oidc_assume_role[0].json
}

resource "aws_iam_role_policy_attachment" "this" {
  policy_arn = aws_iam_policy.this.arn
  role       = aws_iam_role.this.name
}

resource "aws_s3_bucket" "chunks" {
  bucket = "${var.aws_resource_name_prefix}${var.k8s_cluster_name}-loki-chunks"
  acl    = "private"
  force_destroy = true
  tags   = var.aws_tags
  versioning {
    enabled = false
  }
}

resource "kubernetes_service_account" "this" {
  automount_service_account_token = true
  metadata {
    annotations = {
      # This annotation is only used when running on EKS which can
      # use IAM roles for service accounts.
      "eks.amazonaws.com/role-arn" = aws_iam_role.this.arn
    }
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/name"       = "loki"
    }
    name      = "loki"
    namespace = local.k8s_namespace
  }
}

resource "kubernetes_config_map" "rules" {
  data = {
    "rules.yaml" = var.loki_rules
  }
  metadata {
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/name"       = "loki-rules"
    }
    name      = "loki-rules"
    namespace = local.k8s_namespace  
  }
}
resource "kubernetes_config_map" "this" {
  data = {
    "loki.yaml" = yamlencode({
      auth_enabled = false
      ingester = {
        lifecycler = {
          address = "0.0.0.0"
          ring = {
            kvstore = {
              store = "inmemory"
            }
            replication_factor = 1
          }
          final_sleep = "0s"
        }
        chunk_idle_period   = "5m"
        chunk_retain_period = "30s"
      }
      schema_config = {
        configs = [
          {
            from         = "2020-01-01"
            store        = "aws"
            object_store = "s3"
            schema       = "v11"
            index = {
              prefix = "${var.aws_resource_name_prefix}${var.k8s_cluster_name}-loki-index-"
              period = "${24 * 7}h"
            }
          }
        ]
      }
      storage_config = {
        aws = {
          s3 = "s3://${local.aws_region_name}/${aws_s3_bucket.chunks.bucket}"
          dynamodb = {
            dynamodb_url = "dynamodb://${local.aws_region_name}"
          }
        }
      }
      table_manager = {
        retention_deletes_enabled = true
        retention_period          = "${24 * var.retention_days}h"
        index_tables_provisioning = {
          enable_ondemand_throughput_mode : true
          enable_inactive_throughput_on_demand_mode : true
        }
      }
      limits_config = {
        enforce_metric_name        = false
        reject_old_samples         = true
        reject_old_samples_max_age = "168h"
      }
      ruler = {
        alertmanager_url = "http://prometheus-kube-prometheus-alertmanager:9093"
        storage = {
          type = "local"
          local = {
            directory = "/etc/loki/rules/"
          }
        }
        rule_path = "/tmp/scratch"
        #enable_alertmanager_discovery = true
        enable_api = true
        enable_alertmanager_v2: true
        ring = {
          kvstore = {
            store = "inmemory"
          }
        }
      }
    })
  }
  metadata {
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/name"       = "loki"
    }
    name      = "loki"
    namespace = local.k8s_namespace
  }
}

resource "kubernetes_service" "this" {
  metadata {
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/name"       = "loki"
    }
    name      = "loki"
    namespace = local.k8s_namespace
  }
  spec {
    port {
      name        = "grpc-api"
      port        = 81
      protocol    = "TCP"
      target_port = "grpc"
    }
    port {
      name        = "http-api"
      port        = 3100
      protocol    = "TCP"
      target_port = "http"
    }
    selector = {
      "app.kubernetes.io/instance" = "default"
      "app.kubernetes.io/name"     = "loki"
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "this" {
  depends_on = [
    aws_s3_bucket.chunks,
    aws_iam_role_policy_attachment.this
  ]
  metadata {
    annotations = {
      "field.cattle.io/description" = "Loki"
    }
    labels = {
      "app.kubernetes.io/instance"   = "default"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/name"       = "loki"
      "app.kubernetes.io/version"    = "v${local.loki_version}"
    }
    name      = "loki"
    namespace = local.k8s_namespace
  }
  spec {
    replicas = var.k8s_replicas
    selector {
      match_labels = {
        "app.kubernetes.io/instance" = "default"
        "app.kubernetes.io/name"     = "loki"
      }
    }
    template {
      metadata {
        annotations = merge(
          {
            # Annotation which is only used by KIAM and kube2iam.
            # Should be ignored by your cluster if using IAM roles for service accounts, e.g.
            # when running on EKS.
            "iam.amazonaws.com/role" = aws_iam_role.this.arn
            # Whenever the config map changes, we need to re-create our pods.
            "config.loki.grafana.com/sha1" = sha1(kubernetes_config_map.this.data["loki.yaml"])
            "rules.loki.grafana.com/sha1" = sha1(kubernetes_config_map.rules.data["rules.yaml"])
          },
          var.k8s_pod_annotations
        )
        labels = {
          "app.kubernetes.io/instance" = "default"
          "app.kubernetes.io/name"     = "loki"
          "app.kubernetes.io/version"  = "v${local.loki_version}"
        }
      }
      spec {
        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = "kubernetes.io/os"
                  operator = "In"
                  values   = ["linux"]
                }
                match_expressions {
                  key      = "kubernetes.io/arch"
                  operator = "In"
                  values   = ["amd64"]
                }
              }
            }
          }
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values   = ["loki"]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }
        automount_service_account_token = true
        container {
          args = [
            "-log.level=$(LOKI_LOG_LEVEL)",
            "-ring.store=$(LOKI_RING_STORE)",
            "-server.grpc-listen-port=$(LOKI_GRPC_LISTEN_PORT)",
            "-server.http-listen-port=$(LOKI_HTTP_LISTEN_PORT)",
            "-config.file=/etc/loki/loki.yaml"
          ]
          env {
            name  = "LOKI_LOG_LEVEL"
            value = "info"
          }
          env {
            name  = "LOKI_RING_STORE"
            value = "inmemory"
          }
          env {
            name  = "LOKI_GRPC_LISTEN_PORT"
            value = "9095"
          }
          env {
            name  = "LOKI_HTTP_LISTEN_PORT"
            value = "8080"
          }
          image             = local.loki_docker_image
          image_pull_policy = "IfNotPresent"
          name              = "loki"
          port {
            container_port = 8080
            name           = "http"
            protocol       = "TCP"
          }
          port {
            container_port = 9095
            name           = "grpc"
            protocol       = "TCP"
          }
          readiness_probe {
            http_get {
              path = "/ready"
              port = "http"
            }
            initial_delay_seconds = 30
          }
          resources {
            limits = {
              cpu    = var.k8s_pod_container_resources.limits.cpu
              memory = var.k8s_pod_container_resources.limits.memory
            }
            requests = {
              cpu    = var.k8s_pod_container_resources.requests.cpu
              memory = var.k8s_pod_container_resources.requests.memory
            }
          }
          security_context {
            read_only_root_filesystem = false
          }
          termination_message_path = "/dev/termination-log"
          volume_mount {
            mount_path = "/etc/loki"
            name       = "config"
            read_only  = true
          }
          volume_mount {
            mount_path = "/etc/loki/rules"
            name       = "rules"
            read_only  = true
          }          
        }
        dns_policy          = "ClusterFirst"
        host_network        = false
        node_selector       = var.k8s_node_selector
        priority_class_name = var.k8s_priority_class_name
        restart_policy      = "Always"
        security_context {
          fs_group        = 10001
          run_as_group    = 10001
          run_as_non_root = true
          run_as_user     = 10001
        }
        service_account_name             = kubernetes_service_account.this.metadata[0].name
        termination_grace_period_seconds = 30
        dynamic "toleration" {
          for_each = var.k8s_node_tolerations
          content {
            effect   = toleration.value["effect"]
            key      = toleration.value["key"]
            operator = toleration.value["operator"]
            value    = toleration.value["value"]
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.this.metadata[0].name
          }
        }
        volume {
          name = "rules"
          config_map {
            name = kubernetes_config_map.rules.metadata[0].name
          }
        }      
      }
    }
  }

}