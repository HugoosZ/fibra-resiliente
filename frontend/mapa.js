const estadoMapa = document.querySelector("#estado-mapa");
const avisoMapa = document.querySelector("#aviso-mapa");
const attrAntes = document.querySelector("#attr-antes");
const attrDespues = document.querySelector("#attr-despues");
const numeros = new Intl.NumberFormat("es-CL", { maximumFractionDigits: 1 });
const porcentajes = new Intl.NumberFormat("es-CL", { style: "percent", maximumFractionDigits: 2 });

function esProbabilidad(valor) {
  return Number.isFinite(valor) && valor >= 0 && valor <= 1;
}

function formatoProbabilidad(valor) {
  return valor > 0 && valor < 0.0001 ? "menos de 0,01 %" : porcentajes.format(valor);
}

function colorFalla(enlace) {
  const probabilidad = enlace.prob_falla;
  if (enlace.alcance_modelo === "fuera" || !esProbabilidad(probabilidad)) return "--fuera-alcance";
  if (probabilidad === 0) return "--fibra";
  if (probabilidad <= 0.01) return "--falla-baja";
  if (probabilidad <= 0.10) return "--falla-media";
  return "--falla-alta";
}

function textoFalla(enlace) {
  if (enlace.alcance_modelo === "fuera") {
    return "Fuera del alcance del modelo. Se asumió 0 % de falla para la simulación.";
  }
  if (!esProbabilidad(enlace.prob_falla)) return "Probabilidad de falla sin estimar.";
  const texto = `Probabilidad de falla estimada en el 27F: ${formatoProbabilidad(enlace.prob_falla)}.`;
  if (enlace.alcance_modelo === "parcial") {
    return `${texto} Las partes fuera del alcance se simularon con 0 % de falla.`;
  }
  return texto;
}

function actualizarAttr(attr) {
  const inicialDisponible = esProbabilidad(attr?.attr_inicial);
  const posteriorDisponible = esProbabilidad(attr?.attr_posterior);
  const formato = new Intl.NumberFormat("es-CL", { minimumFractionDigits: 2, maximumFractionDigits: 5 });
  attrAntes.textContent = inicialDisponible ? formato.format(attr.attr_inicial) : "No disponible";
  attrDespues.textContent = posteriorDisponible ? formato.format(attr.attr_posterior) : "Pendiente";

  const mensajes = [];
  if (inicialDisponible && [attr.pares_conectados, attr.pares_totales, attr.nodos_clave].every(Number.isFinite)) {
    mensajes.push(`${attr.pares_conectados} de ${attr.pares_totales} pares con camino antes del sismo entre ${attr.nodos_clave} nodos clave.`);
  }
  if (posteriorDisponible && Number.isInteger(attr.simulaciones) && attr.simulaciones > 0) {
    mensajes.push(`Resultado posterior estimado con ${numeros.format(attr.simulaciones)} simulaciones.`);
  }
  if (inicialDisponible && posteriorDisponible) {
    const cambio = (attr.attr_posterior - attr.attr_inicial) * 100;
    if (cambio === 0) {
      mensajes.push("El ATTR se mantiene para estos nodos clave en la simulación. El mapa muestra el riesgo de cada enlace.");
    } else {
      const variacion = new Intl.NumberFormat("es-CL", { signDisplay: "always", maximumFractionDigits: 3 });
      mensajes.push(`Cambio estimado de ${variacion.format(cambio)} puntos porcentuales.`);
    }
  }
  const detalle = document.querySelector("#detalle-attr");
  detalle.textContent = mensajes.join(" ");
  detalle.hidden = mensajes.length === 0;
}

function vincularCapa(mapa, control, capa) {
  function actualizarVisibilidad() {
    if (control.checked) capa.addTo(mapa);
    else mapa.removeLayer(capa);
  }

  control.disabled = false;
  control.addEventListener("change", actualizarVisibilidad);
  actualizarVisibilidad();
}

function crearPopup(titulo, ...lineas) {
  const contenido = document.createElement("div");
  const encabezado = document.createElement("strong");
  encabezado.textContent = titulo;
  contenido.append(encabezado);
  for (const linea of lineas) {
    if (!linea) continue;
    const detalle = document.createElement("div");
    detalle.textContent = linea;
    contenido.append(detalle);
  }
  return contenido;
}

async function iniciarMapa() {
  if (!window.L) {
    avisoMapa.textContent = "No se pudo cargar Leaflet. Revisa la conexión a Internet.";
    avisoMapa.hidden = false;
    estadoMapa.textContent = "Capas no disponibles";
    attrAntes.textContent = "No disponible";
    attrDespues.textContent = "No disponible";
    return;
  }

  const colores = getComputedStyle(document.documentElement);
  const mapa = L.map("mapa", { preferCanvas: true, zoomSnap: 0.25, minZoom: 3 });
  mapa.fitBounds([[-42, -76.5], [-30, -68]]);

  const mapaBase = L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19,
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
  });
  mapaBase.on("tileerror", () => {
    avisoMapa.textContent = "No se pudieron cargar partes del mapa base.";
    avisoMapa.hidden = false;
  });
  mapaBase.on("loading", () => { avisoMapa.hidden = true; });
  mapaBase.addTo(mapa);
  L.control.scale({ imperial: false }).addTo(mapa);

  try {
    const respuesta = await fetch("datos/mapa.geojson");
    if (!respuesta.ok) throw new Error(`HTTP ${respuesta.status}`);
    const datos = await respuesta.json();
    const lineasFibra = datos.features.filter((f) => f.properties.tipo === "fibra");
    const lineasAcceso = datos.features.filter((f) => f.properties.tipo === "acceso");
    const puntosSitio = datos.features.filter((f) => f.properties.tipo === "sitio");
    const sismo = datos.features.find((f) => f.properties.tipo === "sismo");
    if (!lineasFibra.length || !sismo) throw new Error("Falta la fibra observada o el sismo del 27F.");
    const escenario = document.querySelector("#escenario-mapa");
    const hayEscenario = lineasFibra.some(({ properties }) => esProbabilidad(properties.prob_falla));
    const estiloFibra = ({ properties: enlace }) => ({
      color: colores.getPropertyValue(escenario.value === "posterior" ? colorFalla(enlace) : "--fibra").trim(),
      weight: 2.5,
    });
    const fibra = L.geoJSON(lineasFibra, {
      style: estiloFibra,
      onEachFeature({ properties: enlace }, capa) {
        capa.bindPopup(crearPopup(`Enlace observado ${enlace.id}`,
          `${numeros.format(enlace.longitud_m)} m`,
          textoFalla(enlace)));
      },
    });
    if (hayEscenario) {
      const leyenda = document.querySelector("#leyenda-falla");
      const muestra = document.querySelector("#mostrar-fibra + .muestra");
      function cambiarEscenario() {
        const posterior = escenario.value === "posterior";
        fibra.setStyle(estiloFibra);
        leyenda.hidden = !posterior;
        muestra.classList.toggle("por-probabilidad", posterior);
      }
      escenario.value = "posterior";
      escenario.addEventListener("change", cambiarEscenario);
      document.querySelector("#control-escenario").hidden = false;
      document.querySelector("#estado-falla").textContent = "Probabilidades disponibles en Escenario 27F.";
      cambiarEscenario();
    }

    // Mantiene los accesos encima al reactivar la fibra.
    mapa.createPane("accesos").style.zIndex = "410";
    const accesos = L.geoJSON(lineasAcceso, {
      renderer: L.svg({ pane: "accesos" }),
      style: { color: colores.getPropertyValue("--acceso").trim(), weight: 4, dashArray: "7 6" },
      onEachFeature({ properties: enlace }, capa) {
        const supuesto = enlace.alcance_modelo === "supuesto"
          ? "Se supuso operativo para el escenario 27F (0 % de falla)."
          : null;
        capa.bindPopup(crearPopup(`Acceso sintético · ${enlace.nombre}`,
          `${numeros.format(enlace.longitud_m)} m hasta el vértice ${enlace.target}`,
          enlace.justificacion,
          supuesto));
      },
    });

    const sitios = L.geoJSON(puntosSitio, {
      pointToLayer({ properties: sitio }, latLng) {
        const clase = sitio.vertice_terminal === null ? "marca-sitio pendiente" : "marca-sitio";
        return L.marker(latLng, {
          title: sitio.nombre,
          icon: L.divIcon({ className: clase, iconSize: [14, 14] }),
        });
      },
      onEachFeature({ properties: sitio }, capa) {
        let estado = "Pendiente de asociación a la red";
        if (sitio.vertice_terminal !== null) {
          estado = sitio.acceso_sintetico
            ? `Terminal ${sitio.vertice_terminal} unido por acceso sintético al vértice ${sitio.vertice_red}`
            : `Asociado al vértice ${sitio.vertice_terminal}`;
        }
        capa.bindPopup(crearPopup(sitio.nombre, sitio.rol, estado));
      },
    });

    const [longitud, latitud] = sismo.geometry.coordinates;
    const magnitud = numeros.format(sismo.properties.magnitud);
    const fecha = document.querySelector("#sismo-fecha");
    fecha.dateTime = sismo.properties.fecha;
    fecha.textContent = new Intl.DateTimeFormat("es-CL", { dateStyle: "long", timeZone: "UTC" })
      .format(new Date(`${sismo.properties.fecha}T00:00:00Z`));
    document.querySelector("#sismo-magnitud").textContent = magnitud;
    const epicentro = L.marker([latitud, longitud], {
      title: "Epicentro del terremoto del Maule",
      icon: L.divIcon({ className: "marca-epicentro", iconSize: [16, 16] }),
    }).bindPopup(crearPopup("Terremoto del Maule",
      `Magnitud ${magnitud} · profundidad ${numeros.format(sismo.properties.profundidad_km)} km`));

    const mostrarFibra = document.querySelector("#mostrar-fibra");
    const mostrarAccesos = document.querySelector("#mostrar-accesos");
    const mostrarSitios = document.querySelector("#mostrar-sitios");
    const mostrarEpicentro = document.querySelector("#mostrar-epicentro");
    vincularCapa(mapa, mostrarFibra, fibra);
    vincularCapa(mapa, mostrarAccesos, accesos);
    vincularCapa(mapa, mostrarSitios, sitios);
    vincularCapa(mapa, mostrarEpicentro, epicentro);

    const verRed = document.querySelector("#ver-red");
    verRed.disabled = false;
    verRed.addEventListener("click", () => {
      mostrarFibra.checked = true;
      fibra.addTo(mapa);
      mapa.fitBounds(fibra.getBounds(), { padding: [24, 24] });
    });

    const verAccesos = document.querySelector("#ver-accesos");
    const capasAcceso = accesos.getLayers();
    for (const capa of capasAcceso) {
      const { id, nombre } = capa.feature.properties;
      verAccesos.add(new Option(nombre, String(id)));
    }
    verAccesos.disabled = capasAcceso.length === 0;
    verAccesos.addEventListener("change", () => {
      const capa = capasAcceso.find((acceso) => String(acceso.feature.properties.id) === verAccesos.value);
      if (!capa) return;
      mostrarAccesos.checked = true;
      mostrarSitios.checked = true;
      accesos.addTo(mapa);
      sitios.addTo(mapa);
      mapa.fitBounds(capa.getBounds(), { padding: [36, 36], maxZoom: 14 });
      mapa.getContainer().scrollIntoView({ block: "nearest" });
    });

    const verEpicentro = document.querySelector("#ver-epicentro");
    verEpicentro.disabled = false;
    verEpicentro.addEventListener("click", () => {
      mostrarEpicentro.checked = true;
      epicentro.addTo(mapa);
      mapa.setView(epicentro.getLatLng(), 8, { animate: false });
      epicentro.openPopup();
      mapa.getContainer().scrollIntoView({ block: "nearest" });
    });

    document.querySelector("#total-fibra").textContent = numeros.format(lineasFibra.length);
    document.querySelector("#total-accesos").textContent = numeros.format(lineasAcceso.length);
    document.querySelector("#total-sitios").textContent = numeros.format(puntosSitio.length);
    const asociados = puntosSitio.filter((f) => f.properties.vertice_terminal !== null).length;
    estadoMapa.textContent = `${asociados} de ${puntosSitio.length} sitios asociados al modelo.`;
    if (asociados < puntosSitio.length) {
      estadoMapa.textContent += " Los pendientes tienen un marcador vacío.";
    }

    actualizarAttr(datos.attr);
  } catch (error) {
    estadoMapa.textContent = "No se pudieron cargar los datos del mapa.";
    attrAntes.textContent = "No disponible";
    attrDespues.textContent = "No disponible";
    console.error(error);
  }
}

iniciarMapa();
