# Dépannage
```bash
sudo sshd -t
sudo sshd -T
sudo journalctl -b -u ssh.service -n 100 --no-pager
sudo journalctl -b -t sshd -t sshd-session -t sshd-auth -n 100 --no-pager
sudo ss -lntp
```
Client : `ssh -vvv -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 -p PORT UTILISATEUR@SERVEUR`.
Comparer les empreintes avec ssh-keygen -lf. Vérifier les permissions, les règles Match, AllowUsers, le port réel et les pénalités par source si disponibles.
