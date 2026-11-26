#!/usr/bin/env bash
# Gestionnaire SSH Ubuntu — configuration prudente et restauration temporisée.
set -Eeuo pipefail
umask 077
export LC_ALL=C
BASE=/var/lib/ssh-security-manager
CONF=/etc/ssh/sshd_config
SSHD=/usr/sbin/sshd
[[ $EUID == 0 ]] || { echo 'Exécuter avec sudo.'; exit 1; }
mkdir -p "$BASE"; chmod 700 "$BASE"
exec 9>"$BASE/lock"; flock -n 9 || { echo 'Une autre instance est active.'; exit 1; }
. /etc/os-release
[[ ${ID:-} == ubuntu ]] || { echo 'Système non Ubuntu : arrêt.'; exit 1; }
[[ -x $SSHD ]] || { echo 'Installer openssh-server : sudo apt install openssh-server'; exit 1; }
ask(){ local v; read -r -p "$1 [$2] : " v; printf '%s' "${v:-$2}"; }
yesno(){ local v; v=$(ask "$1 (o/n)" n); [[ $v == o ]]; }
info(){ printf '\n%s\n' "$*"; }
# Sélection d’un compte local et contrôle du répertoire personnel.
account(){
 U=$(ask 'Utilisateur local' "${SUDO_USER:-}"); [[ $U =~ ^[a-z_][a-z0-9_-]*\$?$ && $U != root ]] || return 1
 grep -q "^$U:" /etc/passwd || { echo 'Compte local inexistant.'; return 1; }
 H=$(getent passwd "$U" | cut -d: -f6); [[ $H == /* && $H != / && -d $H ]] || return 1
 K="$H/.ssh/authorized_keys"
}
# Les opérations sur les clés se font avec les droits du compte cible.
keys(){
 account || return 1
 local op key
 op=$(ask '1 Ajouter / 2 Lister / 3 Corriger permissions / 4 Supprimer par numéro' 1)
 case $op in
 1) read -r -p 'Coller la clé publique sur UNE ligne : ' key
 [[ $key =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com)[[:space:]] ]] || { echo 'Type de clé refusé.'; return 1; }
 printf '%s\n' "$key" | ssh-keygen -lf /dev/stdin || return 1
 runuser -u "$U" -- bash -c 'set -eu; umask 077; mkdir -p "$1/.ssh"; [[ ! -L "$1/.ssh" && ! -L "$2" ]]; touch "$2"; chmod 700 "$1/.ssh"; chmod 600 "$2"; IFS= read -r k; grep -Fxq -- "$k" "$2" || printf "\n%s\n" "$k" >> "$2"' _ "$H" "$K" <<< "$key" ;;
 2) runuser -u "$U" -- ssh-keygen -lf "$K"; runuser -u "$U" -- nl -ba "$K" ;;
 3) runuser -u "$U" -- bash -c 'set -e; [[ ! -L "$1/.ssh" && ! -L "$2" ]]; chmod go-w "$1"; chmod 700 "$1/.ssh"; chmod 600 "$2"' _ "$H" "$K" ;;
 4) runuser -u "$U" -- nl -ba "$K"; local n; n=$(ask 'Numéro de ligne' 0); [[ $n =~ ^[1-9][0-9]*$ ]] || return 1; yesno 'Confirmer la suppression (risque de perte d’accès)' || return 0; runuser -u "$U" -- bash -c 'set -e; [[ ! -L "$1" ]]; cp -p -- "$1" "$1.bak.$(date +%s)"; sed -i "${2}d" "$1"' _ "$K" "$n" ;;
 *) return 1;; esac
}
# Restauration du fichier principal et du mode d’écoute existant.
cat > "$BASE/restore.sh" <<'RESTORE'
#!/bin/bash
set -eu
b=$1
cp -a "$b/sshd_config" /etc/ssh/sshd_config
/usr/sbin/sshd -t
systemctl daemon-reload
if [[ $(cat "$b/mode") == socket ]]; then
 systemctl stop ssh.service
 systemctl restart ssh.socket
else
 systemctl restart ssh.service
fi
RESTORE
chmod 700 "$BASE/restore.sh"
apply(){
 account || return 1
 local port mode cidr auth tries grace forward penalty src effective b unit tmp oldport
 [[ ! -e $BASE/pending ]] || { echo 'Transaction précédente à vérifier (menu 5).'; return 1; }
 "$SSHD" -t || return 1
 effective=$("$SSHD" -T) || return 1
 oldport=$(awk '$1=="port"{print $2;exit}' <<< "$effective")
 port=$(ask 'Port SSH' "$oldport"); [[ $port =~ ^[1-9][0-9]{0,4}$ ]] && ((port<=65535)) || return 1
 src=${SSH_CONNECTION%% *}; src=${src:-127.0.0.1}
 cidr=$(ask 'Adresse/CIDR autorisé (any = aucune restriction supplémentaire)' "$src")
 if [[ $cidr != any ]]; then python3 -c 'import ipaddress,sys; ipaddress.ip_network(sys.argv[1],strict=True)' "$cidr" || return 1; fi
 auth=$(ask 'Authentification : key ou mixed' key); [[ $auth == key || $auth == mixed ]] || return 1
 if [[ $auth == key ]]; then runuser -u "$U" -- ssh-keygen -lf "$K" || return 1; fi
 tries=$(ask 'MaxAuthTries' 3); grace=$(ask 'LoginGraceTime (secondes)' 30)
 [[ $tries =~ ^[1-9][0-9]?$ && $grace =~ ^[1-9][0-9]{0,2}$ ]] || return 1
 forward=no; yesno 'Autoriser les tunnels SSH (TCP/agent/X11 selon configuration)' && forward=yes
 mode=service; systemctl is-active --quiet ssh.socket && mode=socket
 # Ne pas écraser les configurations existantes : bloc prioritaire, validation effective.
 b=$(mktemp -d "$BASE/backup.XXXXXXXX"); cp -a "$CONF" "$b/sshd_config"; echo "$mode" > "$b/mode"
 tmp=$(mktemp /etc/ssh/.manager.XXXXXXXX)
 {
 echo '# BEGIN SSH SECURITY MANAGER'
 printf 'Port %s\nPubkeyAuthentication yes\nStrictModes yes\nPermitRootLogin no\nMaxAuthTries %s\nLoginGraceTime %s\nMaxStartups 10:30:60\nLogLevel VERBOSE\n' "$port" "$tries" "$grace"
 if [[ $auth == key ]]; then printf 'AuthenticationMethods publickey\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n'; else printf 'AuthenticationMethods any\nPasswordAuthentication yes\nKbdInteractiveAuthentication no\n'; fi
 [[ $cidr == any ]] && printf 'AllowUsers %s\n' "$U" || printf 'AllowUsers %s@%s\n' "$U" "$cidr"
 [[ $forward == yes ]] || echo 'DisableForwarding yes'
 if grep -q '^persourcemaxstartups ' <<< "$effective"; then echo 'PerSourceMaxStartups 5'; fi
 if grep -q '^persourcepenalties ' <<< "$effective"; then
 echo 'PerSourcePenalties yes'
 if [[ $cidr != any ]] && yesno 'Exempter le réseau de confiance des pénalités OpenSSH'; then echo "PerSourcePenaltyExemptList $cidr"; fi
 fi
 echo '# END SSH SECURITY MANAGER'
 awk '/^# BEGIN SSH SECURITY MANAGER$/{skip=1;next} /^# END SSH SECURITY MANAGER$/{skip=0;next} !skip' "$CONF"
 } > "$tmp"
 chmod --reference="$CONF" "$tmp"; chown --reference="$CONF" "$tmp"
 "$SSHD" -t -f "$tmp" || { rm -f "$tmp"; return 1; }
 "$SSHD" -T -f "$tmp" -C "user=$U,host=client,addr=$src" > "$b/effective" || { rm -f "$tmp"; return 1; }
 grep -E '^(port|listenaddress|allowusers|denyusers|allowgroups|denygroups|authenticationmethods|authorizedkeysfile|pubkeyauthentication|passwordauthentication|disableforwarding|persource)' "$b/effective"
 if [[ $auth == key ]] && ! grep -qx 'authenticationmethods publickey' "$b/effective"; then echo 'Conflit Match/Include.'; rm -f "$tmp"; return 1; fi
 info 'Attention : AllowUsers/Port peuvent se cumuler avec les règles existantes. Vérifier les valeurs ci-dessus.'
 info 'Le pare-feu, NAT et les règles externes doivent autoriser le nouveau port AVANT application.'
 command -v ufw >/dev/null && ufw status numbered || true
 yesno 'Accès console disponible, pare-feu vérifié, appliquer avec retour automatique après 5 minutes' || { rm -f "$tmp"; return 0; }
 unit="ssh-manager-rollback-$(date +%s)"
 printf '%s\n%s\n' "$b" "$unit" > "$BASE/pending"
 if ! systemd-run --unit="$unit" --on-active=5min "$BASE/restore.sh" "$b"; then rm -f "$BASE/pending" "$tmp"; return 1; fi
 mv -f "$tmp" "$CONF"
 if ! systemctl daemon-reload || ! { if [[ $mode == socket ]]; then systemctl stop ssh.service && systemctl restart ssh.socket; else systemctl restart ssh.service; fi; }; then
 "$BASE/restore.sh" "$b" && systemctl stop "$unit.timer" && rm -f "$BASE/pending"; return 1
 fi
 ss -lntp
 info "Tester depuis un AUTRE terminal : ssh -o IdentitiesOnly=yes -i CHEMIN_CLE -p $port $U@SERVEUR"
 info 'Ne pas fermer la session actuelle. Confirmer via menu 5 seulement après connexion réussie.'
}
finish(){
 [[ -f $BASE/pending ]] || { echo 'Aucune transaction.'; return 0; }
 local b unit; mapfile -t p < "$BASE/pending"; b=${p[0]}; unit=${p[1]}
 if ! systemctl is-active --quiet "$unit.timer"; then echo 'Minuteur expiré ou arrêté. Vérifier la restauration.'; rm -f "$BASE/pending"; return 0; fi
 if yesno 'Nouvelle connexion indépendante réussie : conserver la configuration'; then systemctl stop "$unit.timer"; rm -f "$BASE/pending"; echo 'Configuration conservée.'; elif yesno 'Restaurer immédiatement'; then "$BASE/restore.sh" "$b" && systemctl stop "$unit.timer" && rm -f "$BASE/pending"; fi
}
firewall(){
 command -v ufw >/dev/null || { echo 'UFW absent.'; return 1; }
 ufw status numbered
 local p a; p=$(ask 'Port à autoriser' 22); a=$(ask 'CIDR source de confiance' ''); [[ $p =~ ^[1-9][0-9]{0,4}$ ]] && ((p<=65535)) || return 1
 python3 -c 'import ipaddress,sys; ipaddress.ip_network(sys.argv[1],strict=True)' "$a" || return 1
 yesno "Ajouter règle UFW $a vers TCP/$p (sans activer UFW)" && ufw allow from "$a" to any port "$p" proto tcp || true
}
while true; do
 printf '\n=== Ubuntu SSH Security Manager | %s ===\n' "$PRETTY_NAME"; "$SSHD" -V 2>&1 || true
 printf '1 Diagnostic\n2 Gestion des clés\n3 Durcissement interactif\n4 Pare-feu UFW\n5 Confirmation / retour arrière\n6 Créer un utilisateur local\n7 Journaux SSH\n0 Quitter\n'
 read -r -p 'Choix : ' choice || exit 0
 case $choice in
 1) "$SSHD" -t && "$SSHD" -T; systemctl status ssh.service ssh.socket --no-pager || true; ss -lntp;;
 2) keys || echo 'Opération interrompue.';;
 3) apply || echo 'Configuration non confirmée : vérifier les messages.';;
 4) firewall || echo 'Opération interrompue.';;
 5) finish || echo 'Vérifier le retour arrière.';;
 6) u=$(ask 'Nom du nouvel utilisateur' ''); if [[ $u =~ ^[a-z_][a-z0-9_-]*$ ]] && ! getent passwd "$u" >/dev/null; then adduser "$u"; if yesno 'Accorder les droits sudo'; then usermod -aG sudo "$u"; fi; fi;;
 7) journalctl -b -u ssh.service -n 100 --no-pager; journalctl -b -t sshd -t sshd-session -t sshd-auth -n 50 --no-pager;;
 0) exit 0;; *) echo 'Choix invalide.';; esac
done
