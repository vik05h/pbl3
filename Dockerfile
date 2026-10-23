# MedCare Healthcare System - Production Dockerfile
# Base image: Lightweight security-hardened Alpine Linux with Nginx
FROM nginx:alpine

# Remove default nginx welcome page
RUN rm -rf /usr/share/nginx/html/*

# Copy modern MedCare DevSecOps & Blue-Green Dashboard
COPY index.html /usr/share/nginx/html/index.html

# Expose standard HTTP port
EXPOSE 80

# Run nginx in foreground
CMD ["nginx", "-g", "daemon off;"]
