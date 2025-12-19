# GitHub Actions Workflow - Archived

This workflow has been archived because the project now uses **Jenkins** for CI/CD instead of GitHub Actions.

## Original Workflow

The original GitHub Actions workflow has been moved to:
- `deploy.yml.backup` (in this directory)

## Current CI/CD

The project now uses **Jenkins Pipeline** for:
- Building Docker images
- Running tests
- Pushing to DockerHub
- Zero-downtime deployment to EC2 servers

## Setup Instructions

For Jenkins setup, see:
- **JENKINS-SETUP.md** - Complete Jenkins installation and configuration guide
- **Jenkinsfile** - Pipeline definition

## Restoration

To restore GitHub Actions workflow:
```bash
mv .github/workflows-archive/deploy.yml.backup .github/workflows/deploy.yml
```

---

**Migration Date**: December 19, 2025  
**Reason**: Client requested Jenkins-based CI/CD pipeline
