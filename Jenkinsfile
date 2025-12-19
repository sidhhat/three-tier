pipeline {
    agent any
    
    environment {
        // Docker Configuration
        DOCKER_IMAGE = 'vishal762/django-notes-app'
        DOCKER_CREDENTIALS_ID = 'dockerhub-credentials'
        DOCKERFILE = 'Dockerfile.production'
        
        // EC2 Configuration
        EC2_SERVER_1 = '44.201.15.190'
        EC2_SERVER_2 = '3.89.89.66'
        EC2_USER = 'ubuntu'
        EC2_SSH_KEY_ID = 'ec2-ssh-key'
        SSH_KEY_PATH = './terraform/django-notes-key.pem'
        
        // Application Configuration
        APP_PORT = '8000'
        CONTAINER_NAME = 'django-notes-app'
        HEALTH_CHECK_TIMEOUT = '120'
        
        // Build Information
        BUILD_TAG = "${env.BUILD_NUMBER}"
        GIT_COMMIT_SHORT = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
    }
    
    stages {
        stage('Checkout') {
            steps {
                script {
                    echo "🔄 Checking out code from GitHub..."
                    checkout scm
                    sh """
                        echo "📌 Current Branch: ${env.GIT_BRANCH}"
                        echo "📌 Commit: ${GIT_COMMIT_SHORT}"
                        echo "📌 Build: ${BUILD_TAG}"
                    """
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    echo "🔨 Building Docker image..."
                    sh """
                        docker build -f ${DOCKERFILE} \
                            -t ${DOCKER_IMAGE}:latest \
                            -t ${DOCKER_IMAGE}:${BUILD_TAG} \
                            -t ${DOCKER_IMAGE}:git-${GIT_COMMIT_SHORT} \
                            .
                        
                        echo "✅ Docker image built successfully"
                        docker images | grep ${DOCKER_IMAGE}
                    """
                }
            }
        }
        
        stage('Test Image') {
            steps {
                script {
                    echo "🧪 Testing Docker image..."
                    sh """
                        # Run container for testing
                        docker run -d --name test-container -p 9000:8000 ${DOCKER_IMAGE}:latest
                        
                        # Wait for application to start
                        sleep 20
                        
                        # Health check
                        curl -f http://localhost:9000/admin/login/ || exit 1
                        
                        # Cleanup
                        docker stop test-container
                        docker rm test-container
                        
                        echo "✅ Image test passed"
                    """
                }
            }
        }
        
        stage('Push to DockerHub') {
            steps {
                script {
                    echo "📤 Pushing image to DockerHub..."
                    withCredentials([usernamePassword(
                        credentialsId: "${DOCKER_CREDENTIALS_ID}",
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )]) {
                        sh """
                            echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin
                            
                            docker push ${DOCKER_IMAGE}:latest
                            docker push ${DOCKER_IMAGE}:${BUILD_TAG}
                            docker push ${DOCKER_IMAGE}:git-${GIT_COMMIT_SHORT}
                            
                            docker logout
                            echo "✅ Images pushed to DockerHub"
                        """
                    }
                }
            }
        }
        
        stage('Deploy to Server 1') {
            steps {
                script {
                    echo "🚀 Deploying to EC2 Server 1 (${EC2_SERVER_1})..."
                    sshagent(credentials: ["${EC2_SSH_KEY_ID}"]) {
                        sh """
                            ssh -o StrictHostKeyChecking=no ${EC2_USER}@${EC2_SERVER_1} '
                                set -e
                                
                                echo "📥 Pulling new image..."
                                docker pull ${DOCKER_IMAGE}:latest
                                
                                # Check if container exists
                                if docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}\$"; then
                                    echo "🔄 Updating existing container..."
                                    
                                    # Stop and remove old container to free port
                                    echo "🛑 Stopping old container..."
                                    docker stop ${CONTAINER_NAME} || true
                                    
                                    echo "🗑️ Removing old container..."
                                    docker rm ${CONTAINER_NAME} || true
                                    
                                    # Wait for port to be released
                                    sleep 2
                                fi
                                
                                # Start new container
                                echo "🚀 Starting new container..."
                                docker run -d \
                                    --name ${CONTAINER_NAME} \
                                    -p ${APP_PORT}:${APP_PORT} \
                                    --restart unless-stopped \
                                    ${DOCKER_IMAGE}:latest
                                
                                # Wait for new container to be healthy
                                echo "⏳ Waiting for container to be healthy..."
                                TIMEOUT=${HEALTH_CHECK_TIMEOUT}
                                COUNTER=0
                                
                                while [ \$COUNTER -lt \$TIMEOUT ]; do
                                    if docker inspect --format=\"{{.State.Health.Status}}\" ${CONTAINER_NAME} 2>/dev/null | grep -q \"healthy\"; then
                                        echo "✅ Container is healthy"
                                        break
                                    fi
                                    if [ \$COUNTER -eq \$TIMEOUT ]; then
                                        echo "❌ Health check timeout"
                                        docker logs ${CONTAINER_NAME}
                                        exit 1
                                    fi
                                    sleep 2
                                    COUNTER=\$((COUNTER + 2))
                                done
                                
                                # Verify deployment
                                curl -f http://localhost:${APP_PORT}/ || exit 1
                                
                                # Cleanup old images
                                docker image prune -f
                                
                                echo "✅ Deployment to Server 1 completed"
                            '
                        """
                    }
                }
            }
        }
        
        stage('Verify Server 1') {
            steps {
                script {
                    echo "🔍 Verifying Server 1 deployment..."
                    sh """
                        curl -f http://${EC2_SERVER_1}:${APP_PORT}/ || exit 1
                        echo "✅ Server 1 is responding"
                    """
                }
            }
        }
        
        stage('Deploy to Server 2') {
            steps {
                script {
                    echo "🚀 Deploying to EC2 Server 2 (${EC2_SERVER_2})..."
                    sshagent(credentials: ["${EC2_SSH_KEY_ID}"]) {
                        sh """
                            ssh -o StrictHostKeyChecking=no ${EC2_USER}@${EC2_SERVER_2} '
                                set -e
                                
                                echo "📥 Pulling new image..."
                                docker pull ${DOCKER_IMAGE}:latest
                                
                                # Check if container exists
                                if docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}\$"; then
                                    echo "🔄 Updating existing container..."
                                    
                                    # Stop and remove old container to free port
                                    echo "🛑 Stopping old container..."
                                    docker stop ${CONTAINER_NAME} || true
                                    
                                    echo "🗑️ Removing old container..."
                                    docker rm ${CONTAINER_NAME} || true
                                    
                                    # Wait for port to be released
                                    sleep 2
                                fi
                                
                                # Start new container
                                echo "🚀 Starting new container..."
                                docker run -d \
                                    --name ${CONTAINER_NAME} \
                                    -p ${APP_PORT}:${APP_PORT} \
                                    --restart unless-stopped \
                                    ${DOCKER_IMAGE}:latest
                                
                                # Wait for new container to be healthy
                                echo "⏳ Waiting for container to be healthy..."
                                TIMEOUT=${HEALTH_CHECK_TIMEOUT}
                                COUNTER=0
                                
                                while [ \$COUNTER -lt \$TIMEOUT ]; do
                                    if docker inspect --format=\"{{.State.Health.Status}}\" ${CONTAINER_NAME} 2>/dev/null | grep -q \"healthy\"; then
                                        echo "✅ Container is healthy"
                                        break
                                    fi
                                    if [ \$COUNTER -eq \$TIMEOUT ]; then
                                        echo "❌ Health check timeout"
                                        docker logs ${CONTAINER_NAME}
                                        exit 1
                                    fi
                                    sleep 2
                                    COUNTER=\$((COUNTER + 2))
                                done
                                
                                # Verify deployment
                                curl -f http://localhost:${APP_PORT}/ || exit 1
                                
                                # Cleanup old images
                                docker image prune -f
                                
                                echo "✅ Deployment to Server 2 completed"
                            '
                        """
                    }
                }
            }
        }
        
        stage('Verify Server 2') {
            steps {
                script {
                    echo "🔍 Verifying Server 2 deployment..."
                    sh """
                        curl -f http://${EC2_SERVER_2}:${APP_PORT}/ || exit 1
                        echo "✅ Server 2 is responding"
                    """
                }
            }
        }
        
        stage('Final Verification') {
            steps {
                script {
                    echo "🎯 Running final verification..."
                    sh """
                        echo "Testing ALB endpoint..."
                        curl -f http://django-notes-alb-1211580729.us-east-1.elb.amazonaws.com/ || echo "ALB check failed"
                        
                        echo ""
                        echo "╔════════════════════════════════════════════════════════════════════╗"
                        echo "║              DEPLOYMENT SUCCESSFUL                                 ║"
                        echo "╚════════════════════════════════════════════════════════════════════╝"
                        echo ""
                        echo "🎉 Build: ${BUILD_TAG}"
                        echo "📦 Image: ${DOCKER_IMAGE}:latest"
                        echo "🔗 Commit: ${GIT_COMMIT_SHORT}"
                        echo ""
                        echo "🌐 Endpoints:"
                        echo "   ALB: http://django-notes-alb-1211580729.us-east-1.elb.amazonaws.com"
                        echo "   Server 1: http://${EC2_SERVER_1}:${APP_PORT}"
                        echo "   Server 2: http://${EC2_SERVER_2}:${APP_PORT}"
                        echo ""
                        echo "╚════════════════════════════════════════════════════════════════════╝"
                    """
                }
            }
        }
    }
    
    post {
        success {
            echo "✅ Pipeline completed successfully!"
        }
        failure {
            echo "❌ Pipeline failed!"
            echo "Check the logs above for details."
        }
        always {
            // Cleanup
            sh """
                docker system prune -f || true
                echo "🧹 Cleanup completed"
            """
        }
    }
}
