# Outdated Node version for "1+ year" requirement [Ref: PDF Page 3]
FROM node:14

# MANDATORY: Candidate identity file [Ref: PDF Page 3]
RUN echo "Rahul Kuppachhi" > /wizexercise.txt

WORKDIR /app
# Minimal app logic that "pretends" to be a web app
RUN echo "console.log('Wiz Web App Tier Running...');" > server.js

EXPOSE 8080
CMD [ "node", "server.js" ]
