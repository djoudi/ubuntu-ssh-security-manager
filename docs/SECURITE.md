# Sécurité et limites
- Conserver une console indépendante et une sauvegarde hors serveur.
- Le retour temporisé couvre sshd_config, pas les comptes, clés ou règles UFW. Il dépend de systemd et ne garantit pas la reprise après redémarrage.
- Vérifier les directives Include, Match, Port et AllowUsers effectives. Les directives cumulatives peuvent conserver des valeurs précédentes.
- Ne pas désactiver les mots de passe avant un test réel de connexion par clé.
- Ne pas activer UFW sans examiner toutes les autres règles nécessaires.
- Fail2Ban n’est pas géré par cette version.
