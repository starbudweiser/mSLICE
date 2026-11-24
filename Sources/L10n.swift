// mSLICE — textes de l'interface : une seule table, quatre langues (fr rédigé en premier, en, es, it).
import Foundation

enum L {
    enum Lang: Int { case fr = 0, en, es, it }

    /// Langue du Mac si c'est l'une des quatre, sinon l'anglais ; `MSLICE_LANG=fr|en|es|it` pour les essais.
    static var lang: Lang = {
        func lang(_ code: String) -> Lang? { switch code { case "fr": .fr; case "en": .en; case "es": .es; case "it": .it; default: nil } }
        if let forced = ProcessInfo.processInfo.environment["MSLICE_LANG"] { return lang(forced) ?? .en }
        return Locale.preferredLanguages.lazy.compactMap { lang(String($0.prefix(2))) }.first ?? .en
    }()

    static func t(_ key: String, _ args: CVarArg...) -> String {
        guard let row = table[key] else { return key }
        let s = row[lang.rawValue]
        return args.isEmpty ? s : String(format: s, arguments: args)
    }

    /// Clés dont une langue manque (utilisé par `--check-l10n`).
    static func problems() -> [String] { table.filter { $0.value.count != 4 || $0.value.contains(where: { $0.isEmpty }) }.map(\.key).sorted() }

    // [fr, en, es, it]
    static let table: [String: [String]] = [part0, part1, part2, part3].reduce(into: [:]) { $0.merge($1) { a, _ in a } }
    private static let part0: [String: [String]] = [
        "unit.gb": ["Go", "GB", "GB", "GB"],
        "unit.mb": ["Mo", "MB", "MB", "MB"],
        "unit.kb": ["Ko", "KB", "KB", "KB"],
        "fmt.same": ["Identique", "Same", "Igual", "Identico"],
        "quality.high": ["Haute", "High", "Alta", "Alta"],
        "quality.medium": ["Moyenne", "Medium", "Media", "Media"],
        "quality.low": ["Basse", "Low", "Baja", "Bassa"],
        "appearance.auto": ["Auto", "Auto", "Auto", "Auto"],
        "appearance.light": ["Clair", "Light", "Claro", "Chiaro"],
        "appearance.dark": ["Sombre", "Dark", "Oscuro", "Scuro"],
        "common.close": ["Fermer", "Close", "Cerrar", "Chiudi"],
        "common.cancel": ["Annuler", "Cancel", "Cancelar", "Annulla"],
        "common.done": ["Terminé", "Done", "Hecho", "Fine"],
        "app.tagline": ["Extrait des morceaux d'un fichier audio ou vidéo, très vite et sans recompression.", "Extract pieces from an audio or video file, fast and without re-encoding.", "Extrae fragmentos de un archivo de audio o vídeo, muy rápido y sin recomprimir.", "Estrae parti da un file audio o video, in fretta e senza ricodifica."],
        "err.noffmpeg": ["Le moteur ffmpeg est introuvable.", "The ffmpeg engine could not be found.", "No se encuentra el motor ffmpeg.", "Il motore ffmpeg non è stato trovato."],
        "err.unsupported": ["« %@ » n'est pas un fichier audio ou vidéo lisible.", "“%@” is not a readable audio or video file.", "«%@» no es un archivo de audio o vídeo legible.", "«%@» non è un file audio o video leggibile."],
        "err.cantcopy": ["Ce format ne peut pas recevoir les flux de l'original sans recompression : choisissez « Identique » ou « Recompresser ».", "This format cannot hold the original streams without re-encoding: choose “Same” or “Re-encode”.", "Este formato no admite los flujos originales sin recomprimir: elige «Igual» o «Recomprimir».", "Questo formato non può contenere i flussi originali senza ricodifica: scegli «Identico» o «Ricodifica»."],
        "err.noaudio": ["Ce fichier n'a pas de piste audio.", "This file has no audio track.", "Este archivo no tiene pista de audio.", "Questo file non ha una traccia audio."],
        "preview.preparing": ["Préparation de l'aperçu…", "Preparing preview…", "Preparando la vista previa…", "Preparazione dell'anteprima…"],
        "bar.shortcuts": ["Raccourcis", "Shortcuts", "Atajos", "Scorciatoie"],
        "files.title": ["Fichiers ouverts · %d", "Open files · %d", "Archivos abiertos · %d", "File aperti · %d"],
        "files.none": ["Aucun fichier ouvert", "No open files", "Ningún archivo abierto", "Nessun file aperto"],
        "files.drop": ["Déposez des fichiers ici", "Drop files here", "Suelta archivos aquí", "Trascina i file qui"],
        "files.dropHint": ["ou clic droit dans le Finder ▸ Extraire avec mSLICE", "or right-click in the Finder ▸ Extract with mSLICE", "o clic derecho en el Finder ▸ Extraer con mSLICE", "o clic destro nel Finder ▸ Estrai con mSLICE"],
        "files.extracted": ["Extrait", "Extracted", "Extraído", "Estratto"],
        "files.piece": ["%d morceau", "%d piece", "%d fragmento", "%d parte"],
        "files.pieces": ["%d morceaux", "%d pieces", "%d fragmentos", "%d parti"],
        "files.close": ["Fermer ce fichier", "Close this file", "Cerrar este archivo", "Chiudi questo file"],
        "empty.title": ["Déposez des fichiers audio ou vidéo", "Drop audio or video files", "Suelta archivos de audio o vídeo", "Trascina file audio o video"],
        "empty.sub": ["ou faites un clic droit dessus dans le Finder ▸ Extraire avec mSLICE", "or right-click them in the Finder ▸ Extract with mSLICE", "o haz clic derecho en el Finder ▸ Extraer con mSLICE", "o fai clic destro nel Finder ▸ Estrai con mSLICE"],
        "empty.choose": ["Choisir des fichiers…", "Choose files…", "Elegir archivos…", "Scegli i file…"],
        "empty.formats": ["Tout ce que ffprobe sait lire : MOV, MP4, MKV, AVI, WebM, MXF, MTS, WAV, AIFF, MP3, AAC, FLAC, OGG, Opus… L'extraction sans recompression garde le codec d'origine.", "Anything ffprobe can read: MOV, MP4, MKV, AVI, WebM, MXF, MTS, WAV, AIFF, MP3, AAC, FLAC, OGG, Opus… Extraction without re-encoding keeps the original codec.", "Todo lo que ffprobe sabe leer: MOV, MP4, MKV, AVI, WebM, MXF, MTS, WAV, AIFF, MP3, AAC, FLAC, OGG, Opus… La extracción sin recomprimir conserva el códec original.", "Tutto ciò che ffprobe sa leggere: MOV, MP4, MKV, AVI, WebM, MXF, MTS, WAV, AIFF, MP3, AAC, FLAC, OGG, Opus… L'estrazione senza ricodifica mantiene il codec originale."],
        "player.inPiece": ["Dans le morceau %d", "In piece %d", "En el fragmento %d", "Nella parte %d"],
        "player.frame": ["image %d · %@ i/s", "frame %d · %@ fps", "imagen %d · %@ fps", "fotogramma %d · %@ fps"],
        "tr.in": ["Entrée", "In", "Entrada", "Entrata"],
        "tr.out": ["Sortie", "Out", "Salida", "Uscita"],
        "tl.zoom": ["Zoom", "Zoom", "Zoom", "Zoom"],
        "tl.snap": ["Aimant : images clés", "Snap: keyframes", "Imán: fotogramas clave", "Magnete: keyframe"],
        "tl.snap.help": ["En copie directe, l'entrée se cale sur l'image clé précédente : le début réel du morceau.", "With direct copy, the in point snaps to the previous keyframe: the actual start of the piece.", "En copia directa, la entrada se ajusta al fotograma clave anterior: el inicio real del fragmento.", "Con la copia diretta, l'entrata si aggancia al keyframe precedente: l'inizio reale della parte."],
        "tl.auto": ["Auto : silences début/fin", "Auto: start/end silence", "Auto: silencios inicio/final", "Auto: silenzi inizio/fine"],
        "tl.auto.none": ["Aucun silence d'ouverture ou de fin détecté.", "No opening or closing silence detected.", "No se detectó silencio de apertura ni de cierre.", "Nessun silenzio iniziale o finale rilevato."],
        "tl.keyframe": ["image clé", "keyframe", "fotograma clave", "keyframe"],
    ]
    private static let part1: [String: [String]] = [
        "key.in": ["entrée", "in", "entrada", "entrata"],
        "key.out": ["sortie", "out", "salida", "uscita"],
        "key.play": ["lecture", "play", "reproducir", "riproduci"],
        "key.speed": ["vitesse", "speed", "velocidad", "velocità"],
        "key.frame": ["image", "frame", "imagen", "fotogramma"],
        "key.keyframe": ["image clé", "keyframe", "fot. clave", "keyframe"],
        "key.delete": ["suppr.", "delete", "borrar", "elimina"],
        "key.in.long": ["Marquer l'entrée du morceau", "Mark the piece's in point", "Marcar la entrada del fragmento", "Segna l'entrata della parte"],
        "key.out.long": ["Marquer la sortie (crée le morceau)", "Mark the out point (creates the piece)", "Marcar la salida (crea el fragmento)", "Segna l'uscita (crea la parte)"],
        "key.second": ["Avancer / reculer d'une seconde", "Step one second", "Avanzar / retroceder un segundo", "Avanti / indietro di un secondo"],
        "key.keyframe.long": ["Image clé suivante / précédente", "Next / previous keyframe", "Fotograma clave siguiente / anterior", "Keyframe successivo / precedente"],
        "key.piece": ["Morceau précédent / suivant", "Previous / next piece", "Fragmento anterior / siguiente", "Parte precedente / successiva"],
        "key.undo": ["Annuler", "Undo", "Deshacer", "Annulla"],
        "key.export": ["Extraire", "Extract", "Extraer", "Estrai"],
        "key.startend": ["Début / fin du fichier", "Start / end of file", "Inicio / fin del archivo", "Inizio / fine del file"],
        "pieces.title": ["Morceaux · %d", "Pieces · %d", "Fragmentos · %d", "Parti · %d"],
        "pieces.kept": ["%@ gardés sur %@", "%@ kept of %@", "%@ conservados de %@", "%@ mantenuti su %@"],
        "pieces.empty": ["Placez la tête de lecture, puis marquez l'entrée et la sortie de chaque morceau à garder.", "Move the playhead, then mark the in and out of each piece to keep.", "Coloca el cabezal y marca la entrada y la salida de cada fragmento que quieras conservar.", "Sposta la testina, poi segna entrata e uscita di ogni parte da tenere."],
        "pieces.shift.lead": ["Sans recompression :", "Without re-encoding:", "Sin recomprimir:", "Senza ricodifica:"],
        "pieces.shift": ["le morceau %d démarre à l'image clé %@ (%@ s avant votre entrée). Recompressez pour couper à l'image près.", "piece %d starts at keyframe %@ (%@ s before your in point). Re-encode to cut to the exact frame.", "el fragmento %d empieza en el fotograma clave %@ (%@ s antes de tu entrada). Recomprime para cortar al fotograma exacto.", "la parte %d inizia al keyframe %@ (%@ s prima della tua entrata). Ricodifica per tagliare al fotogramma esatto."],
        "export.separate": ["Un par morceau", "One per piece", "Uno por fragmento", "Uno per parte"],
        "export.merge": ["Fusionner", "Merge", "Fusionar", "Unisci"],
        "export.passthrough": ["Sans recompression", "No re-encoding", "Sin recomprimir", "Senza ricodifica"],
        "export.recompress": ["Recompresser", "Re-encode", "Recomprimir", "Ricodifica"],
        "export.codec": ["Codec · qualité", "Codec · quality", "Códec · calidad", "Codec · qualità"],
        "export.folder": ["Dossier", "Folder", "Carpeta", "Cartella"],
        "export.sameFolder": ["Même dossier que l'original", "Same folder as the original", "Misma carpeta que el original", "Stessa cartella dell'originale"],
        "export.estSize": ["Taille estimée", "Estimated size", "Tamaño estimado", "Dimensione stimata"],
        "export.estTime": ["Durée du traitement", "Processing time", "Duración del proceso", "Durata dell'elaborazione"],
        "export.baseName": ["Noms des fichiers", "File names", "Nombres de los archivos", "Nomi dei file"],
        "export.mergeNote": ["%d morceaux assemblés bout à bout", "%d pieces joined end to end", "%d fragmentos unidos uno tras otro", "%d parti unite una dopo l'altra"],
        "export.go.n": ["Extraire %d morceaux", "Extract %d pieces", "Extraer %d fragmentos", "Estrai %d parti"],
        "export.go.one": ["Extraire 1 morceau", "Extract 1 piece", "Extraer 1 fragmento", "Estrai 1 parte"],
        "export.go.merged": ["Extraire 1 fichier fusionné", "Extract 1 merged file", "Extraer 1 archivo fusionado", "Estrai 1 file unito"],
        "export.running": ["Extraction en cours", "Extracting", "Extracción en curso", "Estrazione in corso"],
        "export.failed": ["Échec de l'extraction", "Extraction failed", "Falló la extracción", "Estrazione non riuscita"],
        "export.files": ["%d fichiers", "%d files", "%d archivos", "%d file"],
        "export.waiting": ["En attente", "Waiting", "En espera", "In attesa"],
        "export.cancelled": ["Annulé", "Cancelled", "Cancelado", "Annullato"],
        "export.progress": ["%d %% terminé", "%d%% done", "%d%% completado", "%d%% completato"],
        "done.title": ["%d fichiers créés", "%d files created", "%d archivos creados", "%d file creati"],
    ]
    private static let part2: [String: [String]] = [
        "done.sub": ["%@ · %@ s · dans le dossier choisi", "%@ · %@ s · in the chosen folder", "%@ · %@ s · en la carpeta elegida", "%@ · %@ s · nella cartella scelta"],
        "done.trash": ["Mettre l'original à la corbeille", "Move the original to the Trash", "Mover el original a la papelera", "Sposta l'originale nel Cestino"],
        "done.reveal": ["Révéler dans le Finder", "Reveal in Finder", "Mostrar en el Finder", "Mostra nel Finder"],
        "menu.about": ["À propos de mSLICE", "About mSLICE", "Acerca de mSLICE", "Informazioni su mSLICE"],
        "menu.settings": ["Réglages…", "Settings…", "Ajustes…", "Impostazioni…"],
        "menu.quit": ["Quitter mSLICE", "Quit mSLICE", "Salir de mSLICE", "Esci da mSLICE"],
        "menu.hide": ["Masquer mSLICE", "Hide mSLICE", "Ocultar mSLICE", "Nascondi mSLICE"],
        "menu.file": ["Fichier", "File", "Archivo", "File"],
        "menu.open": ["Ouvrir…", "Open…", "Abrir…", "Apri…"],
        "menu.export": ["Extraire", "Extract", "Extraer", "Estrai"],
        "menu.closeFile": ["Fermer le fichier", "Close file", "Cerrar archivo", "Chiudi file"],
        "menu.edit": ["Édition", "Edit", "Edición", "Modifica"],
        "menu.undo": ["Annuler", "Undo", "Deshacer", "Annulla"],
        "menu.window": ["Fenêtre", "Window", "Ventana", "Finestra"],
        "menu.minimize": ["Réduire", "Minimize", "Minimizar", "Riduci"],
        "menu.shortcuts": ["Raccourcis clavier", "Keyboard shortcuts", "Atajos de teclado", "Scorciatoie da tastiera"],
        "settings.title": ["Réglages", "Settings", "Ajustes", "Impostazioni"],
        "settings.general": ["Général", "General", "General", "Generale"],
        "settings.language": ["Langue", "Language", "Idioma", "Lingua"],
        "settings.language.auto": ["Automatique (langue du Mac)", "Automatic (Mac language)", "Automático (idioma del Mac)", "Automatica (lingua del Mac)"],
        "settings.appearance": ["Apparence", "Appearance", "Apariencia", "Aspetto"],
        "settings.export": ["Export", "Export", "Exportación", "Esportazione"],
        "settings.digits": ["Chiffres de la numérotation", "Numbering digits", "Dígitos de la numeración", "Cifre della numerazione"],
        "settings.suffix": ["Nom du fichier fusionné", "Merged file name", "Nombre del archivo fusionado", "Nome del file unito"],
        "settings.reveal": ["Révéler dans le Finder après l'export", "Reveal in Finder after export", "Mostrar en el Finder tras exportar", "Mostra nel Finder dopo l'esportazione"],
        "settings.trash": ["Mettre l'original à la corbeille après l'export", "Move the original to the Trash after export", "Mover el original a la papelera tras exportar", "Sposta l'originale nel Cestino dopo l'esportazione"],
        "settings.finder": ["Finder", "Finder", "Finder", "Finder"],
        "settings.finder.ext": ["Extension du clic droit", "Right-click extension", "Extensión del clic derecho", "Estensione del clic destro"],
        "settings.finder.on": ["Active", "Active", "Activa", "Attiva"],
        "settings.finder.off": ["Non activée", "Not enabled", "No activada", "Non attiva"],
        "settings.finder.open": ["Réglages Système…", "System Settings…", "Ajustes del Sistema…", "Impostazioni di Sistema…"],
        "settings.update": ["Mises à jour", "Updates", "Actualizaciones", "Aggiornamenti"],
        "settings.autoUpdate": ["Installer automatiquement", "Install automatically", "Instalar automáticamente", "Installa automaticamente"],
        "settings.updateNow": ["Rechercher maintenant", "Check now", "Buscar ahora", "Cerca ora"],
        "settings.version": ["Version %@", "Version %@", "Versión %@", "Versione %@"],
        "settings.about": ["À propos de mSLICE · DESKTOP MAC TOOLKIT", "About mSLICE · DESKTOP MAC TOOLKIT", "Acerca de mSLICE · DESKTOP MAC TOOLKIT", "Informazioni su mSLICE · DESKTOP MAC TOOLKIT"],
        "about.version": ["Version %@ (%@)", "Version %@ (%@)", "Versión %@ (%@)", "Versione %@ (%@)"],
        "about.collection": ["Fait partie du DESKTOP MAC TOOLKIT", "Part of the DESKTOP MAC TOOLKIT", "Parte del DESKTOP MAC TOOLKIT", "Parte del DESKTOP MAC TOOLKIT"],
        "about.support": ["Soutenir le projet", "Support the project", "Apoyar el proyecto", "Sostieni il progetto"],
        "batch.title": ["Élaguer début et fin", "Trim start and end", "Recortar inicio y final", "Taglia inizio e fine"],
    ]
    private static let part3: [String: [String]] = [
        "batch.files": ["%d fichiers", "%d files", "%d archivos", "%d file"],
        "batch.start": ["Retirer au début", "Remove from the start", "Quitar al inicio", "Rimuovi all'inizio"],
        "batch.end": ["Retirer à la fin", "Remove from the end", "Quitar al final", "Rimuovi alla fine"],
        "batch.silence": ["Ou détecter les silences d'ouverture et de fin", "Or detect opening and closing silence", "O detectar los silencios de apertura y cierre", "Oppure rileva i silenzi iniziali e finali"],
        "batch.passthrough": ["Sans recompression (coupe à l'image clé)", "No re-encoding (cuts at the keyframe)", "Sin recomprimir (corta en el fotograma clave)", "Senza ricodifica (taglia al keyframe)"],
        "batch.result": ["Résultat : %@, … dans le même dossier. Les originaux ne sont jamais modifiés.", "Result: %@, … in the same folder. Originals are never modified.", "Resultado: %@, … en la misma carpeta. Los originales nunca se modifican.", "Risultato: %@, … nella stessa cartella. Gli originali non vengono mai modificati."],
        "batch.go": ["Élaguer %d fichiers", "Trim %d files", "Recortar %d archivos", "Taglia %d file"],
        "batch.go.one": ["Élaguer 1 fichier", "Trim 1 file", "Recortar 1 archivo", "Taglia 1 file"],
        "batch.running": ["Traitement : %@", "Processing: %@", "Procesando: %@", "Elaborazione: %@"],
        "batch.done": ["%d fichiers élagués", "%d files trimmed", "%d archivos recortados", "%d file tagliati"],
        "batch.skipped": ["%@ : trop court pour retirer %@ s + %@ s", "%@: too short to remove %@ s + %@ s", "%@: demasiado corto para quitar %@ s + %@ s", "%@: troppo breve per rimuovere %@ s + %@ s"],
        "batch.seconds": ["s", "s", "s", "s"],
    ]
}
