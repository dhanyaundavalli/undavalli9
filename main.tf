provider "aws" {

  region = "ca-central-1"

}

resource "aws_vpc" "dhanya_main_vpc" {

  cidr_block = "10.0.0.0/16"

}

resource "aws_internet_gateway" "dhanya_main_igw" {

  vpc_id = aws_vpc.dhanya_main_vpc.id

}

resource "aws_subnet" "dhanya_private_subnet_1a" {

  vpc_id            = aws_vpc.dhanya_main_vpc.id

  cidr_block        = "10.0.1.0/24"

  availability_zone = "ca-central-1a"

}

resource "aws_subnet" "dhanya_private_subnet_1b" {

  vpc_id            = aws_vpc.dhanya_main_vpc.id

  cidr_block        = "10.0.2.0/24"

  availability_zone = "ca-central-1b"

}

resource "aws_subnet" "dhanya_public_subnet_1a" {

  vpc_id                  = aws_vpc.dhanya_main_vpc.id

  cidr_block              = "10.0.3.0/24"

  availability_zone       = "ca-central-1a"

  map_public_ip_on_launch = true

}

resource "aws_eip" "dhanya_nat_eip" {

}

resource "aws_route_table" "dhanya_public_rt" {

  vpc_id = aws_vpc.dhanya_main_vpc.id

}

resource "aws_route" "dhanya_public_internet_route" {

  route_table_id         = aws_route_table.dhanya_public_rt.id

  destination_cidr_block = "0.0.0.0/0"

  gateway_id             = aws_internet_gateway.dhanya_main_igw.id

}

resource "aws_route_table_association" "dhanya_public_rta" {

  subnet_id      = aws_subnet.dhanya_public_subnet_1a.id

  route_table_id = aws_route_table.dhanya_public_rt.id

}

resource "aws_nat_gateway" "dhanya_nat_gateway" {

  allocation_id = aws_eip.dhanya_nat_eip.id

  subnet_id     = aws_subnet.dhanya_public_subnet_1a.id

}

resource "aws_route_table" "dhanya_private_rt" {

  vpc_id = aws_vpc.dhanya_main_vpc.id

}

resource "aws_route" "dhanya_private_internet_route" {

  route_table_id         = aws_route_table.dhanya_private_rt.id

  destination_cidr_block = "0.0.0.0/0"

  nat_gateway_id         = aws_nat_gateway.dhanya_nat_gateway.id

}

resource "aws_route_table_association" "dhanya_private_rta_1" {

  subnet_id      = aws_subnet.dhanya_private_subnet_1a.id

  route_table_id = aws_route_table.dhanya_private_rt.id

}

resource "aws_route_table_association" "dhanya_private_rta_2" {

  subnet_id      = aws_subnet.dhanya_private_subnet_1b.id

  route_table_id = aws_route_table.dhanya_private_rt.id

}

resource "aws_security_group" "dhanya_ecs_sg" {

  vpc_id = aws_vpc.dhanya_main_vpc.id

  ingress {

    from_port   = 80

    to_port     = 80

    protocol    = "tcp"

    cidr_blocks = ["0.0.0.0/0"]

  }

  egress {

    from_port   = 0

    to_port     = 0

    protocol    = "-1"

    cidr_blocks = ["0.0.0.0/0"]

  }

}

resource "aws_ecs_cluster" "dhanya_ecs_cluster" {

  name = "dhanya-flask-ecs-cluster"

}

resource "aws_ecr_repository" "dhanya_flask_ecr" {

  name                 = "flask-app-repo-dhanya"

  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {

    scan_on_push = true

  }

  tags = {

    Environment = "Production"

  }

}

resource "aws_ecs_task_definition" "dhanya_ecs_task" {

  family                   = "dhanya-flask-app-task"

  network_mode             = "awsvpc"

  requires_compatibilities = ["FARGATE"]

  cpu                      = "256"

  memory                   = "512"

  execution_role_arn       = aws_iam_role.dhanya_ecs_exec_role.arn

  task_role_arn            = aws_iam_role.dhanya_ecs_exec_role.arn

  container_definitions = <<DEFINITION

[{

  "name": "dhanya-flask-container",

  "image": "${aws_ecr_repository.dhanya_flask_ecr.repository_url}:latest",

  "essential": true,

  "portMappings": [{

    "containerPort": 80,

    "hostPort": 80

  }]

}]

DEFINITION

}

resource "aws_iam_role" "dhanya_ecs_exec_role" {

  name = "dhanya-ecs-execution-role"

  assume_role_policy = jsonencode({

    Version = "2012-10-17"

    Statement = [

      {

        Action    = "sts:AssumeRole"

        Effect    = "Allow"

        Principal = {

          Service = "ecs-tasks.amazonaws.com"

        }

      }

    ]

  })

}

resource "aws_iam_role_policy_attachment" "dhanya_ecs_exec_role_policy" {

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"

  role       = aws_iam_role.dhanya_ecs_exec_role.name

}

resource "aws_ecs_service" "dhanya_ecs_service" {

  name            = "dhanya-ecs-service"

  cluster         = aws_ecs_cluster.dhanya_ecs_cluster.id

  task_definition = aws_ecs_task_definition.dhanya_ecs_task.arn

  desired_count   = 2

  launch_type     = "FARGATE"

  network_configuration {

    subnets         = [aws_subnet.dhanya_private_subnet_1a.id, aws_subnet.dhanya_private_subnet_1b.id]

    security_groups = [aws_security_group.dhanya_ecs_sg.id]

    assign_public_ip = false

  }

  load_balancer {

    target_group_arn = aws_lb_target_group.dhanya_target_group.arn

    container_name   = "dhanya-flask-container"

    container_port   = 80

  }

}

resource "aws_lb" "dhanya_alb" {

  name               = "dhanya-alb"

  internal           = false

  load_balancer_type = "application"

  security_groups    = [aws_security_group.dhanya_ecs_sg.id]

  subnets            = [aws_subnet.dhanya_private_subnet_1a.id, aws_subnet.dhanya_private_subnet_1b.id]

}

resource "aws_lb_listener" "dhanya_alb_listener" {

  load_balancer_arn = aws_lb.dhanya_alb.arn

  port              = 80

  protocol          = "HTTP"

  default_action {

    type             = "forward"

    target_group_arn = aws_lb_target_group.dhanya_target_group.arn

  }

}

resource "aws_lb_target_group" "dhanya_target_group" {

  name       = "dhanya-target-group"

  port       = 80

  protocol   = "HTTP"

  vpc_id     = aws_vpc.dhanya_main_vpc.id

  target_type = "ip"

}

resource "aws_appautoscaling_target" "dhanya_scaling_target" {

  max_capacity       = 5

  min_capacity       = 2

  resource_id        = "service/${aws_ecs_cluster.dhanya_ecs_cluster.name}/${aws_ecs_service.dhanya_ecs_service.name}"

  scalable_dimension = "ecs:service:DesiredCount"

  service_namespace  = "ecs"

}

resource "aws_appautoscaling_policy" "dhanya_scaling_policy" {

  name               = "dhanya-scaling-policy"

  policy_type        = "TargetTrackingScaling"

  resource_id        = aws_appautoscaling_target.dhanya_scaling_target.resource_id

  scalable_dimension = aws_appautoscaling_target.dhanya_scaling_target.scalable_dimension

  service_namespace  = aws_appautoscaling_target.dhanya_scaling_target.service_namespace

  target_tracking_scaling_policy_configuration {

    target_value       = 50.0

    predefined_metric_specification {

      predefined_metric_type = "ECSServiceAverageCPUUtilization"

    }

    scale_in_cooldown  = 300

    scale_out_cooldown = 300

  }

} 