1. El Makefile (Automatización y Control)
El Makefile es tu panel de mandos.

Comando: ssh-keygen -t ed25519 -f conf/onion_key -q -N ""

-t ed25519: Especifica el tipo (type) de algoritmo criptográfico. ED25519 es el estándar moderno, más seguro y rápido que RSA.

-f conf/onion_key: Especifica el fichero (file) de salida donde se guardará la llave.

-q: Modo quiet (silencioso). Evita que el comando imprima texto innecesario en la pantalla (como el "arte ASCII" que suele generar SSH).

-N "": Establece una Nueva frase de paso (passphrase) vacía. Así no te pedirá contraseña cada vez que uses la llave.

Comando: docker run -d --name $(CONTAINER_NAME) $(IMAGE_NAME)

-d: Ejecuta el contenedor en modo detached (segundo plano). Te devuelve el control de la terminal.

--name: Le asigna un nombre amigable (my_onion) en lugar de uno aleatorio.

Nota de Defensa: Si el evaluador pregunta por qué no hay un -p 80:80, debes responder: "El subject prohíbe abrir puertos hacia el host. El aislamiento debe ser total, el tráfico solo entra por la red Tor".

Comando SSH de prueba: torsocks ssh -i /tmp/onion_key_tmp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 4242 onionuser@$$ONION_URL

torsocks: Enruta el tráfico del comando siguiente a través de tu túnel Tor local.

-i /tmp/...: Especifica el archivo de identidad (tu llave privada).

-o StrictHostKeyChecking=no: Le dice a SSH que no te pregunte "Are you sure you want to continue connecting?" si la llave del servidor es nueva.

-o UserKnownHostsFile=/dev/null: Envía el registro de máquinas conocidas a un "agujero negro" (/dev/null) en lugar de guardarlo en tu PC. Evita el famoso error de "Man-in-the-Middle" cuando reconstruyes el contenedor.

-p 4242: Especifica el puerto al que quieres conectarte.

2. El Dockerfile (Construcción de la Imagen)
Aquí defines cómo se instala y configura el sistema operativo base.

Comando: useradd -m -s /bin/bash onionuser

useradd: Crea un usuario nuevo en Debian.

-m: Obliga al sistema a crear la carpeta home del usuario (/home/onionuser), necesaria para guardar sus llaves SSH.

-s /bin/bash: Define la shell por defecto del usuario. Así, al entrar por SSH, tendrás una consola funcional.

Los Permisos Octales (chmod 700 y 600)

chmod 700 /home/onionuser/.ssh: El número 7 significa que el propietario puede Leer (4) + Escribir (2) + Ejecutar (1) la carpeta. Los ceros significan que el grupo y los demás no pueden hacer nada.

chmod 600 /home/onionuser/.ssh/authorized_keys: El propietario puede Leer (4) + Escribir (2) el archivo, pero no ejecutarlo (porque es texto plano). SSH es sumamente paranoico y rechazará la conexión si estos permisos no son estrictamente estos.

Comando de limpieza: RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh

sed: Es un editor de texto en línea de comandos.

-i: Realiza el cambio in-place (sobreescribe el archivo original en lugar de solo imprimir el resultado).

's/\r$//': Es una expresión regular que busca los retornos de carro de Windows (\r) al final de la línea ($) y los elimina (//). Evita que el script falle si alguna vez se editó en Windows.

3. El entrypoint.sh (El Motor de Arranque)
Este script se ejecuta cuando el contenedor cobra vida.

Comandos con &: nginx &

El ampersand (&) al final manda el proceso a ejecutarse en segundo plano (background). Esto es vital porque en nginx.conf tienes daemon off;, lo que haría que Nginx bloqueara la terminal para siempre. Con el &, la consola queda libre para ejecutar la siguiente línea.

Comando: su -s /bin/bash debian-tor -c "tor -f /etc/tor/torrc" &

su: Ejecuta un comando como si fueras otro usuario (substitute user). Por seguridad, Tor nunca debe ejecutarse como root.

-s /bin/bash: Obliga a usar bash temporalmente para lanzar el comando.

debian-tor: Es el usuario nativo sin privilegios que se creó automáticamente al instalar Tor en Debian.

-c "...": El comando exacto que queremos que ejecute ese usuario.

tor -f /etc/tor/torrc: Arranca el servicio Tor indicándole que lea el fichero (file) de configuración específico que tú creaste.

Comando: tail -f /dev/null

tail -f: Se queda leyendo continuamente (follow) las últimas líneas de un archivo.

/dev/null: Es un archivo vacío de Linux que nunca cambia.

El truco: Como lee un archivo vacío para siempre, el script nunca termina. En Docker, si el entrypoint termina, el contenedor se apaga. Esto mantiene el servidor encendido indefinidamente.

4. Fortificación (Bonus de Seguridad en sshd_config)
Aquí están los puntos del Bonus. Debes saber defender por qué los has puesto:

Port 4242: El puerto estándar de SSH es el 22. Cambiarlo a 4242 (como pide el subject) evita los ataques automatizados de bots que solo buscan en el puerto 22.

PermitRootLogin no: Si un atacante entra, lo primero que intentará es ser administrador. Al bloquear al root directamente, le cortas el acceso total al sistema.

PasswordAuthentication no: Elimina la posibilidad de ataques de "fuerza bruta" o diccionarios de contraseñas. O tienes la llave física (criptográfica), o no entras.

AllowUsers onionuser: Es una "lista blanca". Si alguien descubre un usuario oculto en el sistema e intenta conectarse, SSH lo rechazará porque no está explícitamente en esta lista.

5. Configuración de Red Oculta (torrc y nginx.conf)
torrc (El Puente Oculto):

HiddenServiceDir /var/lib/tor/hidden_service/: Le dice a Tor dónde guardar de forma segura su clave privada y el archivo hostname (que contiene tu dirección .onion).

HiddenServicePort 80 127.0.0.1:80: Instrucción vital. Le dice a Tor: "Todo el tráfico que llegue a la Dark Web por el puerto 80, envíalo a mi red local (127.0.0.1) en el puerto 80". Es un proxy inverso dentro del propio contenedor.

nginx.conf:

daemon off;: Por defecto, Nginx se desconecta de la terminal y se ejecuta en segundo plano. En arquitecturas Docker, se recomienda forzar a los programas principales a ejecutarse en primer plano, porque Docker necesita "ver" el proceso activo. Si un demonio se esconde, Docker a veces piensa que el servicio se ha caído y reinicia el contenedor.