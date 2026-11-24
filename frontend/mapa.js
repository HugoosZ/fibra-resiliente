const estadoMapa = document.querySelector("#estado-mapa");
const avisoMapa = document.querySelector("#aviso-mapa");
const numeros = new Intl.NumberFormat("es-CL", { maximumFractionDigits: 1 });

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
    const fibra = L.geoJSON(lineasFibra, {
      style: { color: colores.getPropertyValue("--fibra").trim(), weight: 2.5 },
      onEachFeature({ properties: enlace }, capa) {
        capa.bindPopup(crearPopup(`Enlace observado ${enlace.id}`, `${numeros.format(enlace.longitud_m)} m`));
      },
    });

    // Mantener los accesos encima de la fibra al cambiar la visibilidad de las capas.
    mapa.createPane("accesos").style.zIndex = "410";
    const accesos = L.geoJSON(lineasAcceso, {
      renderer: L.svg({ pane: "accesos" }),
      style: { color: colores.getPropertyValue("--acceso").trim(), weight: 4, dashArray: "7 6" },
      onEachFeature({ properties: enlace }, capa) {
        capa.bindPopup(crearPopup(`Acceso sintético · ${enlace.nombre}`,
          `${numeros.format(enlace.longitud_m)} m hasta el vértice ${enlace.target}`,
          enlace.justificacion));
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
  } catch (error) {
    estadoMapa.textContent = "No se pudieron cargar los datos del mapa.";
    console.error(error);
  }
}

iniciarMapa();
