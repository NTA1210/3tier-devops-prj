@Library('Shared') _

pipeline {
    agent any

    parameters {
        string(name: 'GIT_REPO', defaultValue: 'https://github.com/NTA1210/3tier-devops-prj.git', description: 'Git repository URL used by the pipeline')
        string(name: 'GIT_BRANCH', defaultValue: 'main', description: 'Git branch to clone and update')
        string(name: 'DOCKERHUB_NAMESPACE', defaultValue: 'nguyentuananhkn7', description: 'Docker Hub namespace or username')
        string(name: 'APP_IMAGE_NAME', defaultValue: 'easyshop-app', description: 'Main application image name')
        string(name: 'MIGRATION_IMAGE_NAME', defaultValue: 'easyshop-migration', description: 'Database migration image name')
        string(name: 'DOCKER_CREDENTIALS_ID', defaultValue: 'docker-hub-credentials', description: 'Jenkins credential ID for Docker Hub')
        string(name: 'GIT_CREDENTIALS_ID', defaultValue: 'github-credentials', description: 'Jenkins credential ID for GitHub')
        string(name: 'MANIFESTS_PATH', defaultValue: 'kubernetes', description: 'Path to Kubernetes manifests')
        string(name: 'GIT_USER_NAME', defaultValue: 'Jenkins CI', description: 'Git username for manifest update commits')
        string(name: 'GIT_USER_EMAIL', defaultValue: 'nguyenanh@example.com', description: 'Git email for manifest update commits')
    }

    environment {
        DOCKER_IMAGE_NAME = "${params.DOCKERHUB_NAMESPACE}/${params.APP_IMAGE_NAME}"
        DOCKER_MIGRATION_IMAGE_NAME = "${params.DOCKERHUB_NAMESPACE}/${params.MIGRATION_IMAGE_NAME}"
        DOCKER_IMAGE_TAG = "${BUILD_NUMBER}"
    }
    
    stages {
        stage('Cleanup Workspace') {
            steps {
                cleanupWorkspace()
            }
        }
        
        stage('Clone Repository') {
            steps {
                checkoutRepo(params.GIT_REPO, params.GIT_BRANCH)
            }
        }
        
        stage('Build Docker Images') {
            parallel {
                stage('Build Main App Image') {
                    steps {
                        buildDockerImage(
                            imageName: env.DOCKER_IMAGE_NAME,
                            imageTag: env.DOCKER_IMAGE_TAG,
                            dockerfile: 'Dockerfile',
                            context: '.'
                        )
                    }
                }
                
                stage('Build Migration Image') {
                    steps {
                        buildDockerImage(
                            imageName: env.DOCKER_MIGRATION_IMAGE_NAME,
                            imageTag: env.DOCKER_IMAGE_TAG,
                            dockerfile: 'scripts/Dockerfile.migration',
                            context: '.'
                        )
                    }
                }
            }
        }
        
        stage('Run Unit Tests') {
            steps {
                runUnitTests()
            }
        }
        
        stage('Security Scan with Trivy') {
            steps {
                trivyScan()
            }
        }
        
        stage('Push Docker Images') {
            parallel {
                stage('Push Main App Image') {
                    steps {
                        pushDockerImage(
                            imageName: env.DOCKER_IMAGE_NAME,
                            imageTag: env.DOCKER_IMAGE_TAG,
                            credentials: params.DOCKER_CREDENTIALS_ID
                        )
                    }
                }
                
                stage('Push Migration Image') {
                    steps {
                        pushDockerImage(
                            imageName: env.DOCKER_MIGRATION_IMAGE_NAME,
                            imageTag: env.DOCKER_IMAGE_TAG,
                            credentials: params.DOCKER_CREDENTIALS_ID
                        )
                    }
                }
            }
        }
        
        stage('Update Kubernetes Manifests') {
            steps {
                updateK8sManifests(
                    imageTag: env.DOCKER_IMAGE_TAG,
                    manifestsPath: params.MANIFESTS_PATH,
                    gitCredentials: params.GIT_CREDENTIALS_ID,
                    gitUserName: params.GIT_USER_NAME,
                    gitUserEmail: params.GIT_USER_EMAIL
                )
            }
        }
    }
}
