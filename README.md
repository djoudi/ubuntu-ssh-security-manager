# Ubuntu SSH Security Manager

Gestion interactive d’OpenSSH sur Ubuntu. Cibles : 22.04, 24.04, 26.04 et versions ultérieures, sous réserve de validation.

## Démarrage

```bash
sudo apt install openssh-server python3 util-linux
chmod +x ubuntu-ssh-security-manager.sh
sudo ./ubuntu-ssh-security-manager.sh
```

UFW est facultatif. Utiliser une console indépendante et un instantané avant toute modification. Ajouter une clé publique, vérifier le pare-feu, puis appliquer le durcissement. Tester une deuxième connexion avant confirmation dans le menu 5.

## Fonctions
Diagnostic, comptes locaux, clés publiques, durcissement, règles UFW, journaux, restauration temporisée de sshd_config.

## Documentation
- [Installation](docs/INSTALLATION.md)
- [Sécurité](docs/SECURITE.md)
- [Dépannage](docs/DEPANNAGE.md)
- [Validation](docs/VALIDATION.md)

## Statut
Prototype v1.0.0 : contrôle syntaxique Bash uniquement. Pas de certification de compatibilité ni de validation en production. Ne pas exécuter sans console de secours.
