docker login
docker build -t mynginx2 .
docker image tag mynginx2 kin3303/mynginx2
docker push kin3303/mynginx2