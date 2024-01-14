provider "aws" {
  region = "ap-southeast-1"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = ["vpc-0ce95cb965ee966f8"]
  }
}

# Fetch information about each subnet
data "aws_subnet" "default" {
  for_each = data.aws_subnets.default.ids
  id       = each.value
}

resource "aws_ecs_cluster" "my_cluster" {
  name = "monitor-backend"
}

# Graphite-StatsD Task Definition
resource "aws_ecs_task_definition" "graphite_statsd" {
  family                   = "graphite-statsd"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = "arn:aws:iam::654654483406:role/ecsTaskExecutionRole"

  container_definitions = jsonencode([
    {
      name      = "statsd"
      image     = "graphiteapp/graphite-statsd"
      cpu       = 512
      memory    = 1024
      essential = true
      portMappings = [
        # Define all your port mappings here
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/graphite-statsd"
          awslogs-region        = "ap-southeast-1"
          awslogs-stream-prefix = "graphite-statsd"
        }
      }
    }
  ])

  # Define volume for EFS
  volume {
    name = "graphite-volume"

    efs_volume_configuration {
      file_system_id     = "fs-0f1b0c937d4ebee21"
      root_directory     = "/"
      transit_encryption = "ENABLED"
    }
  }
}

# NodeJS App Task Definition
resource "aws_ecs_task_definition" "nodejs_app" {
  family                   = "nodejs-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = "arn:aws:iam::654654483406:role/ecsTaskExecutionRole"

  container_definitions = jsonencode([
    {
      name      = "nodejs-app"
      image     = "654654483406.dkr.ecr.ap-southeast-1.amazonaws.com/devops-test-anurak:latest"
      cpu       = 128
      memory    = 256
      essential = true
      environment = [
        {
          name  = "METRICSHOST"
          value = "statsd"
        },
        {
          name  = "METRICSPORT"
          value = "8125"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/graphite-statsd"
          awslogs-region        = "ap-southeast-1"
          awslogs-stream-prefix = "nodejs-app"
        }
      }
    }
  ])
}

# Network Load Balancer
resource "aws_lb" "monitor" {
  name               = "monitor"
  internal           = false
  load_balancer_type = "network"
  subnets = values(data.aws_subnet.default)[*].id
}

# Target Group for Graphite-StatsD
resource "aws_lb_target_group" "graphite_statsd" {
  name     = "graphite-statsd"
  port     = 8125
  protocol = "UDP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

# Listener for the Load Balancer
resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.monitor.arn
  port              = "8125"
  protocol          = "UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.graphite_statsd.arn
  }
}

#ECS Service for Graphite-StatsD
resource "aws_ecs_service" "graphite_statsd_service" {
  name            = "graphite-statsd-service"
  cluster         = aws_ecs_cluster.my_cluster.id
  task_definition = aws_ecs_task_definition.graphite_statsd.arn
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = ["sg-099072f21752c87cd"]
  }

  desired_count = 2 # Adjust as needed for high availability

  load_balancer {
    target_group_arn = aws_lb_target_group.graphite_statsd.arn
    container_name   = "statsd"
    container_port   = 8125
  }
}

#ECS Service for NodeJS App
resource "aws_ecs_service" "nodejs_app_service" {
  name            = "nodejs-app-service"
  cluster         = aws_ecs_cluster.my_cluster.id
  task_definition = aws_ecs_task_definition.nodejs_app.arn
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = ["sg-099072f21752c87cd"]
  }

  desired_count = 2 # Adjust as needed for high availability
}
