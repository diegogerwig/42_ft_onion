# ft_onion — Guía de Defensa

Guía técnica completa para la defensa del proyecto. Cubre la arquitectura, el propósito de cada archivo y los puntos clave que puede preguntar un evaluador.

---

## Arquitectura general

```
                    INTERNET / TOR NETWORK
                           │
                    [Tor Browser / torsocks]
                           │
                    ┌──────▼──────┐
                    │  Tor daemon │   ← gestiona la identidad .onion
                    │ (debian-tor)│
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              │                         │
        puerto 80                  puerto 4242
              │                         │
       ┌──────▼──────┐         ┌────────▼────────┐
       │    Nginx    │         │   OpenSSH sshd  │
       │  (HTTP web) │         │  (acceso shell) │
       └──────┬──────┘         └────────┬────────┘
              │                         │
         index.html               onionuser
              │                  (solo clave ED25519)
        /var/www/html
```

Todo el tráfico entra y sale exclusivamente por la red Tor. **No hay ningún puerto expuesto al host** (`docker run` sin `-p`), lo cual es un requisito explícito del subject.

---

## Flujo de arranque

Cuando se ejecuta `make all`, ocurre lo siguiente en orden:

1. **`make onion_key`** — Genera el par de claves ED25519 en `conf/` si no existen.
2. **`docker build`** — Construye la imagen copiando configuraciones y compilando la imagen base Debian.
3. **`docker run -d`** — Lanza el contenedor en segundo plano.
4. **`entrypoint.sh`** — Dentro del contenedor, arranca `sshd`, `nginx` y `tor` en ese orden.
5. **Bootstrap de Tor (~10s)** — Tor genera la clave del hidden service, escribe la dirección `.onion` en `/var/lib/tor/hidden_service/hostname` y establece el circuito.
6. **`make onion`** — Lee y muestra la dirección `.onion` generada.

---

## Archivos del proyecto

### `Dockerfile`

Define la imagen del contenedor a partir de `debian:bullseye-slim`.

**Paquetes instalados:**

| Paquete | Función |
|---|---|
| `nginx` | Servidor web que sirve `index.html` |
| `tor` | Crea el túnel de red anónimo y gestiona la dirección `.onion` |
| `openssh-server` | Daemon SSH accesible por la red Tor |
| `openssh-client` | Permite hacer `ssh` desde dentro del contenedor (test local) |

**Puntos clave:**

```dockerfile
RUN useradd -m -s /bin/bash onionuser
```
- `-m` → crea `/home/onionuser/`, necesaria para el directorio `.ssh`
- `-s /bin/bash` → shell funcional al conectar por SSH

```dockerfile
RUN chmod 700 /home/onionuser/.ssh
RUN chmod 600 /home/onionuser/.ssh/authorized_keys
```
- `700` → solo el propietario puede entrar al directorio (SSH lo rechaza si es más permisivo)
- `600` → solo lectura/escritura del propietario sobre las claves (requisito estricto de OpenSSH)

```dockerfile
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh
```
- Elimina los retornos de carro de Windows (`\r`) que romperían el script en Linux si el archivo se editó en Windows.

```dockerfile
RUN ssh-keygen -A
```
- Genera las claves del host SSH (`/etc/ssh/ssh_host_*`). Sin esto, `sshd` no puede arrancar.

---

### `src/entrypoint.sh`

Script de arranque que se ejecuta al iniciar el contenedor.

```bash
#!/bin/bash

mkdir -p /run/sshd           # Directorio PID requerido por sshd

/usr/sbin/sshd               # Arranca SSH en primer plano brevemente, luego se daemoniza solo

nginx &                      # Nginx en segundo plano (daemon off; en nginx.conf lo requiere)

su -s /bin/bash debian-tor -c "tor -f /etc/tor/torrc" &   # Tor como usuario sin privilegios

echo "Waiting for the Tor network to bootstrap..."

sleep 10                     # Tiempo para que Tor establezca el circuito

tail -f /dev/null            # Mantiene el contenedor vivo indefinidamente
```

**Por qué `tail -f /dev/null`:** Docker termina el contenedor si el proceso principal (PID 1 = entrypoint.sh) acaba. Como los servicios corren en background con `&`, el script llegaría al final y mataría todo. Este comando bloquea para siempre leyendo un archivo vacío, manteniendo el contenedor activo.

**Por qué Tor corre como `debian-tor`:** Tor tiene protecciones internas que le impiden arrancar como root. `debian-tor` es el usuario sin privilegios creado automáticamente al instalar el paquete en Debian.

---

### `conf/torrc`

Configuración del daemon Tor.

```
HiddenServiceDir /var/lib/tor/hidden_service/
HiddenServicePort 80 127.0.0.1:80
HiddenServicePort 4242 127.0.0.1:4242
```

- **`HiddenServiceDir`** → Tor guarda aquí la clave privada del hidden service y el archivo `hostname` con la dirección `.onion`. El directorio debe pertenecer a `debian-tor` con permisos `700`.
- **`HiddenServicePort`** → Actúa como proxy inverso interno: todo el tráfico que llega por la red Tor al puerto indicado se redirige a `localhost` en ese mismo puerto.

> **Punto de defensa:** La dirección `.onion` es un hash criptográfico derivado de la clave pública del hidden service, no una IP. Es estable mientras no se elimine el contenedor (o la carpeta del hidden service).

---

### `conf/sshd_config`

Configuración del daemon SSH con hardening de seguridad.

```
Port 4242
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
AllowUsers onionuser
```

| Directiva | Motivo de seguridad |
|---|---|
| `Port 4242` | Requerido por el subject. Evita bots que escanean el puerto 22 |
| `PermitRootLogin no` | Impide que un atacante tome control total del sistema |
| `PasswordAuthentication no` | Elimina ataques de fuerza bruta / diccionario |
| `PubkeyAuthentication yes` | Solo se entra con la clave criptográfica correcta |
| `AllowUsers onionuser` | Lista blanca: cualquier otro usuario del sistema es rechazado |

---

### `conf/nginx.conf`

Configuración del servidor web.

```nginx
daemon off;
```

> **Punto clave:** Por defecto Nginx se desacopla de la terminal y se ejecuta en background. En Docker, si el proceso desaparece de la vista del PID manager, el contenedor puede pensar que falló. `daemon off;` fuerza a Nginx a quedarse en primer plano, controlado por el `&` del entrypoint.

El servidor escucha en `0.0.0.0:80` y sirve `/var/www/html/index.html`. Tor redirige el tráfico `.onion:80` a este puerto internamente.

---

### `conf/index.html`

Página estática servida a través del hidden service. Diseño minimalista con tema oscuro y fuente monoespaciada, coherente con el entorno de red Tor.

---

### `Makefile`

Panel de control del proyecto.

| Regla | Descripción |
|---|---|
| `make all` | Construye, arranca, espera 10s, muestra logs y dirección `.onion` |
| `make build` | Genera claves SSH si no existen y construye la imagen sin caché |
| `make run` | Arranca el contenedor en segundo plano |
| `make onion` | Imprime la dirección `.onion` activa |
| `make test-ssh-tor` | Conecta por SSH a través de Tor (requiere `torsocks` en el host) |
| `make test-ssh-local` | Conecta por SSH a `127.0.0.1:4242` dentro del contenedor (sin Tor) |
| `make clean` | Para y elimina el contenedor |
| `make fclean` | Elimina contenedor, imagen y claves generadas |
| `make re` | Reconstrucción completa desde cero |

**Generación de claves:**

```bash
ssh-keygen -t ed25519 -f conf/onion_key -q -N ""
```

| Flag | Significado |
|---|---|
| `-t ed25519` | Algoritmo moderno, más seguro y compacto que RSA |
| `-f conf/onion_key` | Ruta de salida (genera `onion_key` y `onion_key.pub`) |
| `-q` | Modo silencioso, sin arte ASCII |
| `-N ""` | Sin passphrase, para no requerir contraseña al usar la clave |

**Comando de conexión SSH por Tor:**

```bash
torsocks ssh -i conf/onion_key \
             -o StrictHostKeyChecking=no \
             -o UserKnownHostsFile=/dev/null \
             -p 4242 \
             onionuser@<address>.onion
```

| Flag | Motivo |
|---|---|
| `torsocks` | Enruta la conexión SSH por el proxy Tor local |
| `-i conf/onion_key` | Identidad (clave privada) a usar |
| `StrictHostKeyChecking=no` | No pregunta confirmación en la primera conexión |
| `UserKnownHostsFile=/dev/null` | No guarda la huella del host; evita el error MITM al reconstruir el contenedor |
| `-p 4242` | Puerto SSH no estándar definido en `sshd_config` |

---

## Preguntas frecuentes en defensa

**¿Por qué no hay `-p` en `docker run`?**
El subject lo prohíbe expresamente. El aislamiento debe ser total: ningún puerto del contenedor se expone al host. El único punto de entrada es la red Tor.

**¿Cómo se genera la dirección `.onion`?**
Tor deriva la dirección como un hash de la clave pública del hidden service (v3 onion = 56 caracteres en base32). No es una IP registrada en ningún DNS. Mientras el directorio del hidden service no se borre, la dirección es estable.

**¿Qué pasaría si alguien intenta conectarse con contraseña?**
`PasswordAuthentication no` en `sshd_config` hace que el daemon rechace ese método de autenticación directamente, sin ni siquiera procesarlo.

**¿Por qué ED25519 y no RSA?**
ED25519 usa criptografía de curva elíptica: claves más cortas, operaciones más rápidas y resistencia a ataques de canal lateral que afectan a implementaciones RSA.

**¿Cómo verías la dirección `.onion` si el Makefile no existiera?**
```bash
docker exec my_onion cat /var/lib/tor/hidden_service/hostname
```

**¿Cómo probarías que el SSH funciona sin Tor?**
```bash
make test-ssh-local
# equivale a:
docker exec -it my_onion ssh -i /tmp/onion_key_tmp -o StrictHostKeyChecking=no -p 4242 onionuser@127.0.0.1
```

**¿Por qué `sleep 10` en el entrypoint?**
Tor necesita tiempo para establecer el circuito de anonimización y registrar el hidden service en la red. Menos de 10 segundos y el `hostname` podría no estar escrito todavía.