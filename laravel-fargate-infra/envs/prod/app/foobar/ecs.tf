# Redis の状態を参照するためのデータソース追加
data "terraform_remote_state" "cache_foobar" {
  backend = "s3"

  config = {
    bucket = "jyouhou.net-tfstate"
    key    = "example/prod/cache/foobar_v1.0.0.tfstate"
    region = "ap-northeast-1"
  }
}

resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-${local.service_name}"

  tags = {
    Name = "${local.name_prefix}-${local.service_name}"
  }
}

# キャパシティプロバイダーの警告を解消するためのリソース分離
resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }
}

resource "aws_ecs_task_definition" "this" {
  family = "${local.name_prefix}-${local.service_name}"

  task_role_arn = aws_iam_role.ecs_task.arn
  network_mode  = "awsvpc"

  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  memory = "512"
  cpu    = "256"

  container_definitions = jsonencode(
    [
      {
        name  = "nginx"
        image = "${module.nginx.ecr_repository_this_repository_url}:latest"

        portMappings = [
          {
            containerPort = 80
            protocol      = "tcp"
          }
        ]

        environment = [
          {
            name  = "VPC_CIDR"
            value = "171.32.0.0/16"
          }
        ]

        dependsOn = [
          {
            containerName = "php"
            condition     = "START"
          }
        ]

        mountPoints = [
          {
            containerPath = "/var/run/php-fpm"
            sourceVolume  = "php-fpm-socket"
          }
        ]

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = "/ecs/${local.name_prefix}-${local.service_name}/nginx"
            awslogs-region        = data.aws_region.current.id
            awslogs-stream-prefix = "ecs"
          }
        }
      },
      {
        name  = "php"
        image = "${module.php.ecr_repository_this_repository_url}:latest"

        portMappings = []

        # 直接値を渡すものは environment に記述
        environment = [
          {
            name  = "DB_USERNAME"
            value = local.service_name
          },
          {
            name  = "DB_DATABASE"
            value = local.service_name
          },
          # Redis 接続設定の追加
          {
            name  = "REDIS_HOST"
            value = data.terraform_remote_state.cache_foobar.outputs.elasticache_replication_group_this_primary_endpoint_address
          },
          {
            name  = "CACHE_DRIVER"
            value = "redis"
          },
          {
            name  = "SESSION_DRIVER"
            value = "redis"
          }
        ]

        # パラメータストアから取得するものは secrets に記述
        secrets = [
          {
            name      = "APP_KEY"
            valueFrom = "/${local.system_name}/${local.env_name}/${local.service_name}/APP_KEY"
          },
          {
            name      = "DB_PASSWORD"
            valueFrom = "/${local.system_name}/${local.env_name}/${local.service_name}/DB_PASSWORD"
          },
          {
            name      = "DB_HOST"
            valueFrom = "/${local.system_name}/${local.env_name}/${local.service_name}/DB_HOST"
          }
        ]

        mountPoints = [
          {
            containerPath = "/var/run/php-fpm"
            sourceVolume  = "php-fpm-socket"
          }
        ]

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = "/ecs/${local.name_prefix}-${local.service_name}/php"
            awslogs-region        = data.aws_region.current.id
            awslogs-stream-prefix = "ecs"
          }
        }
      }
    ]
  )

  volume {
    name = "php-fpm-socket"
  }

  tags = {
    Name = "${local.name_prefix}-${local.service_name}"
  }
}

resource "aws_ecs_service" "this" {
  name = "${local.name_prefix}-${local.service_name}"

  cluster = aws_ecs_cluster.this.arn

  platform_version = "1.4.0"
  task_definition  = aws_ecs_task_definition.this.arn

  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  load_balancer {
    container_name   = "nginx"
    container_port   = 80
    target_group_arn = data.terraform_remote_state.routing_appfoobar_link.outputs.lb_target_group_foobar_arn
  }

  health_check_grace_period_seconds = 60

  network_configuration {
    assign_public_ip = false
    security_groups  = [data.terraform_remote_state.network_main.outputs.security_group_vpc_id]
    subnets          = [for s in data.terraform_remote_state.network_main.outputs.subnet_private : s.id]
  }

  enable_execute_command = true

  tags = {
    Name = "${local.name_prefix}-${local.service_name}"
  }
}