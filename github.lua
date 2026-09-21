require "import"
import "android.app.*"
import "android.content.*"
import "android.widget.*"
import "android.view.*"
import "android.os.*"
import "android.net.Uri"
import "android.util.Base64"
import "android.widget.ScrollView"
import "java.io.*"
import "java.net.URL"
import "java.net.HttpURLConnection"
import "java.lang.Thread"
import "java.lang.Runnable"
import "org.json.JSONObject"
import "org.json.JSONArray"

local mainHandler = Handler(Looper.getMainLooper())

-- Pengaturan nama SharedPreferences dan kunci unik
local PREF_NAME = "github_acc_manager_exclusive_unique_cfg"
local KEY_TOKEN = "key_github_user_pat_unique"
local prefs = service.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)

-- Deklarasi fungsi navigasi bertingkat
local menuUtama, tampilkanDialogLogin
local buatRepoDialog, tambahFileRepoDialog
local daftarRepoSayaDialog, kelolaRepoPilihanDialog, bukaDirektoriRepoDialog, menuAksiFile, formEditIsiBerkas, gantiNamaRepoDialog

-- Tautan otomatis membuat token dengan izin 'repo'
local URL_GENERATE_TOKEN = "https://github.com/settings/tokens/new?description=Aksesibilitas+Android&scopes=repo"

-- Fungsi penonaktif teks kapital bawaan Android (memaksa huruf kecil agar ramah pembaca layar)
local function aturTombolHurufKecil(diag, teksPositif, teksNegatif, teksNetral)
  pcall(function()
    if teksPositif then
      local btnPos = diag.getButton(DialogInterface.BUTTON_POSITIVE)
      if btnPos then
        btnPos.setTextAllCaps(false)
        btnPos.setTransformationMethod(nil)
        btnPos.setText(teksPositif)
      end
    end
    if teksNegatif then
      local btnNeg = diag.getButton(DialogInterface.BUTTON_NEGATIVE)
      if btnNeg then
        btnNeg.setTextAllCaps(false)
        btnNeg.setTransformationMethod(nil)
        btnNeg.setText(teksNegatif)
      end
    end
    if teksNetral then
      local btnNeu = diag.getButton(DialogInterface.BUTTON_NEUTRAL)
      if btnNeu then
        btnNeu.setTextAllCaps(false)
        btnNeu.setTransformationMethod(nil)
        btnNeu.setText(teksNetral)
      end
    end
  end)
end

-- Fungsi membuka URL ke peramban
local function bukaBrowser(urlTarget)
  local ok, err = pcall(function()
    local intent = Intent(Intent.ACTION_VIEW, Uri.parse(urlTarget))
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    service.startActivity(intent)
  end)
  if not ok then
    Toast.makeText(service, "Gagal membuka browser: " .. tostring(err), Toast.LENGTH_SHORT).show()
  end
end

-- Fungsi menyalin teks ke papan klip
local function salinKeClipboard(label, teks)
  local clipboard = service.getSystemService(Context.CLIPBOARD_SERVICE)
  local clip = ClipData.newPlainText(label, teks)
  clipboard.setPrimaryClip(clip)
  if service.speak then service.speak(label .. " berhasil disalin.") end
  Toast.makeText(service, label .. " disalin!", Toast.LENGTH_SHORT).show()
end

-- Fungsi membagikan tautan via menu Share Android
local function bagikanTautan(judul, teks)
  local ok, err = pcall(function()
    local intent = Intent(Intent.ACTION_SEND)
    intent.setType("text/plain")
    intent.putExtra(Intent.EXTRA_SUBJECT, judul)
    intent.putExtra(Intent.EXTRA_TEXT, teks)
    local chooser = Intent.createChooser(intent, "Bagikan tautan via")
    chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    service.startActivity(chooser)
  end)
  if not ok then
    Toast.makeText(service, "Gagal membagikan: " .. tostring(err), Toast.LENGTH_SHORT).show()
  end
end

-- Permintaan HTTP API GitHub pada thread latar belakang
local function kirimPermintaanGitHub(metode, endpoint, token, jsonBody, onSelesai)
  local progress = ProgressDialog(service)
  progress.setTitle("Menghubungkan ke GitHub")
  progress.setMessage("Sedang memproses permintaan...")
  progress.setCancelable(false)
  progress.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
  progress.show()

  Thread(Runnable{
    run = function()
      local ok, res = pcall(function()
        local url = URL(endpoint)
        local conn = url.openConnection()

        -- Penanganan metode PATCH agar kompatibel dengan seluruh versi Android
        if metode == "PATCH" then
          local okPatch = pcall(function() conn.setRequestMethod("PATCH") end)
          if not okPatch then
            conn.setRequestMethod("POST")
            conn.setRequestProperty("X-HTTP-Method-Override", "PATCH")
          end
        else
          conn.setRequestMethod(metode)
        end

        conn.setRequestProperty("Authorization", "Bearer " .. token)
        conn.setRequestProperty("User-Agent", "Android-Accessibility-Manager")
        conn.setRequestProperty("Accept", "application/vnd.github.v3+json")
        conn.setRequestProperty("Content-Type", "application/json")
        conn.setConnectTimeout(15000)
        conn.setReadTimeout(20000)

        if jsonBody ~= nil and jsonBody ~= "" then
          conn.setDoOutput(true)
          local os = conn.getOutputStream()
          os.write(String(jsonBody).getBytes("UTF-8"))
          os.flush()
          os.close()
        end

        local respCode = conn.getResponseCode()
        local inputStream = (respCode >= 200 and respCode < 300) and conn.getInputStream() or conn.getErrorStream()
        local reader = BufferedReader(InputStreamReader(inputStream, "UTF-8"))
        local lines = {}
        local line = reader.readLine()
        while line ~= nil do
          table.insert(lines, tostring(line))
          line = reader.readLine()
        end
        reader.close()

        local hasil = table.concat(lines, "\n")
        if respCode >= 200 and respCode < 300 then
          return hasil
        else
          local pesanError = "Gagal. Kode HTTP: " .. respCode
          pcall(function()
            local jsonErr = JSONObject(hasil)
            pesanError = pesanError .. " (" .. jsonErr.optString("message", "") .. ")"
          end)
          error(pesanError)
        end
      end)

      mainHandler.post(Runnable{
        run = function()
          pcall(function() progress.dismiss() end)
          onSelesai(ok, res)
        end
      })
    end
  }).start()
end

-- ==========================================================
-- NAVIGASI BERTINGKAT REPOSITORI & BERKAS
-- ==========================================================

-- 1. Menampilkan Semua Repositori Milik Akun
daftarRepoSayaDialog = function(token)
  local endpoint = "https://api.github.com/user/repos?sort=updated&per_page=100&affiliation=owner"
  kirimPermintaanGitHub("GET", endpoint, token, nil, function(ok, res)
    if not ok then
      Toast.makeText(service, "Gagal mengambil daftar repositori: " .. tostring(res), Toast.LENGTH_LONG).show()
      return
    end

    local arr = JSONArray(res)
    local total = arr.length()
    if total == 0 then
      if service.speak then service.speak("Anda belum memiliki repositori.") end
      Toast.makeText(service, "Belum ada repositori ditemukan.", Toast.LENGTH_SHORT).show()
      menuUtama()
      return
    end

    local listItems = {}
    local repoDataList = {}
    for i = 0, total - 1 do
      local item = arr.getJSONObject(i)
      local nama = item.optString("name", "")
      local isPrivate = item.optBoolean("private", false)
      local statusPrivasi = isPrivate and "[privat]" or "[publik]"
      
      table.insert(listItems, string.format("%d. %s %s", i + 1, nama, statusPrivasi))
      table.insert(repoDataList, item)
    end

    if service.speak then service.speak("Ditemukan " .. total .. " repositori.") end

    local b = AlertDialog.Builder(service)
    b.setTitle("Repositori saya (" .. total .. ")")
    b.setItems(listItems, DialogInterface.OnClickListener{
      onClick = function(dialog, which)
        local terpilih = repoDataList[which + 1]
        kelolaRepoPilihanDialog(terpilih, token)
      end
    })
    b.setNegativeButton("kembali", DialogInterface.OnClickListener{
      onClick = function()
        menuUtama()
      end
    })
    local diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.show()
    aturTombolHurufKecil(diag, nil, "kembali", nil)
  end)
end

-- 2. Menu Pengelolaan Repositori Tertentu
kelolaRepoPilihanDialog = function(repoObj, token)
  local namaRepo = repoObj.optString("name", "")
  local fullName = repoObj.optString("full_name", "")
  local htmlUrl = repoObj.optString("html_url", "")

  local subMenus = {
    "1. Jelajahi dan kelola berkas di dalamnya",
    "2. Tambah berkas baru ke repo ini",
    "3. Ganti nama repositori ini",
    "4. Salin tautan halaman repositori",
    "5. Bagikan tautan repositori",
    "6. Buka repositori di browser"
  }

  local b = AlertDialog.Builder(service)
  b.setTitle("Repositori: " .. namaRepo)
  b.setItems(subMenus, DialogInterface.OnClickListener{
    onClick = function(dialog, which)
      if which == 0 then
        bukaDirektoriRepoDialog(fullName, "", token, repoObj)
      elseif which == 1 then
        tambahFileRepoDialog(token, fullName, repoObj)
      elseif which == 2 then
        gantiNamaRepoDialog(repoObj, token)
      elseif which == 3 then
        salinKeClipboard("Tautan repositori", htmlUrl)
      elseif which == 4 then
        bagikanTautan("Tautan repositori: " .. namaRepo, htmlUrl)
      elseif which == 5 then
        bukaBrowser(htmlUrl)
      end
    end
  })
  b.setNegativeButton("kembali", DialogInterface.OnClickListener{
    onClick = function()
      daftarRepoSayaDialog(token)
    end
  })
  local diag = b.create()
  diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
  diag.show()
  aturTombolHurufKecil(diag, nil, "kembali", nil)
end

-- 3. Dialog Ganti Nama Repositori
gantiNamaRepoDialog = function(repoObj, token)
  local namaLama = repoObj.optString("name", "")
  local fullName = repoObj.optString("full_name", "")

  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(40, 20, 40, 10)

  local lblInfo = TextView(service)
  lblInfo.setText("Nama baru repositori (tanpa spasi):")
  layout.addView(lblInfo)

  local inputNamaBaru = EditText(service)
  inputNamaBaru.setText(namaLama)
  inputNamaBaru.setSingleLine(true)
  layout.addView(inputNamaBaru)

  local scroll = ScrollView(service)
  scroll.setFillViewport(true)
  scroll.addView(layout)

  local b = AlertDialog.Builder(service)
  b.setTitle("Ganti nama: " .. namaLama)
  b.setView(scroll)
  b.setPositiveButton("simpan nama baru", DialogInterface.OnClickListener{
    onClick = function(dialog, which)
      local namaBaru = tostring(inputNamaBaru.getText()):match("^%s*(.-)%s*$")
      if namaBaru == "" then
        Toast.makeText(service, "Nama repositori tidak boleh kosong!", Toast.LENGTH_SHORT).show()
        return
      end

      if namaBaru == namaLama then
        Toast.makeText(service, "Nama repositori belum diubah.", Toast.LENGTH_SHORT).show()
        kelolaRepoPilihanDialog(repoObj, token)
        return
      end

      local payload = JSONObject()
      payload.put("name", namaBaru)

      local endpoint = "https://api.github.com/repos/" .. fullName
      kirimPermintaanGitHub("PATCH", endpoint, token, payload.toString(), function(ok, res)
        if ok then
          local updatedObj = JSONObject(res)
          if service.speak then service.speak("Nama repositori berhasil diubah menjadi " .. namaBaru) end
          Toast.makeText(service, "Nama repositori diperbarui!", Toast.LENGTH_SHORT).show()
          kelolaRepoPilihanDialog(updatedObj, token)
        else
          Toast.makeText(service, "Gagal mengubah nama: " .. tostring(res), Toast.LENGTH_LONG).show()
          kelolaRepoPilihanDialog(repoObj, token)
        end
      end)
    end
  })
  b.setNegativeButton("kembali", DialogInterface.OnClickListener{
    onClick = function()
      kelolaRepoPilihanDialog(repoObj, token)
    end
  })

  local diag = b.create()
  diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
  diag.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
  diag.show()
  aturTombolHurufKecil(diag, "simpan nama baru", "kembali", nil)
end

-- 4. Penjelajah Berkas & Sub-folder Repositori
bukaDirektoriRepoDialog = function(fullName, currentPath, token, repoObj)
  local endpoint = "https://api.github.com/repos/" .. fullName .. "/contents/" .. currentPath
  kirimPermintaanGitHub("GET", endpoint, token, nil, function(ok, res)
    if not ok then
      Toast.makeText(service, "Gagal memuat isi folder: " .. tostring(res), Toast.LENGTH_LONG).show()
      return
    end

    local itemsArr = JSONArray(res)
    local total = itemsArr.length()
    local menuItems = {}
    local dataItems = {}

    if currentPath ~= "" then
      table.insert(menuItems, "Folder .. (kembali ke folder sebelumnya)")
      table.insert(dataItems, {tipe = "kembali_folder"})
    end

    for i = 0, total - 1 do
      local item = itemsArr.getJSONObject(i)
      local tipe = item.optString("type", "")
      local name = item.optString("name", "")
      local awalan = (tipe == "dir") and "Folder " or "Berkas "

      table.insert(menuItems, awalan .. name)
      table.insert(dataItems, {
        tipe = tipe,
        name = name,
        path = item.optString("path", ""),
        sha = item.optString("sha", ""),
        html_url = item.optString("html_url", ""),
        download_url = item.optString("download_url", "")
      })
    end

    local judul = (currentPath == "") and ("Berkas: " .. fullName) or ("Folder: " .. currentPath)
    local b = AlertDialog.Builder(service)
    b.setTitle(judul)

    if #menuItems == 0 then
      b.setMessage("Folder ini masih kosong.")
    else
      b.setItems(menuItems, DialogInterface.OnClickListener{
        onClick = function(dialog, which)
          local data = dataItems[which + 1]
          if data.tipe == "kembali_folder" then
            local parentPath = currentPath:match("^(.*)/[^/]+$") or ""
            bukaDirektoriRepoDialog(fullName, parentPath, token, repoObj)
          elseif data.tipe == "dir" then
            bukaDirektoriRepoDialog(fullName, data.path, token, repoObj)
          else
            menuAksiFile(fullName, data, token, currentPath, repoObj)
          end
        end
      })
    end

    b.setNegativeButton("kembali", DialogInterface.OnClickListener{
      onClick = function()
        if currentPath == "" then
          kelolaRepoPilihanDialog(repoObj, token)
        else
          local parentPath = currentPath:match("^(.*)/[^/]+$") or ""
          bukaDirektoriRepoDialog(fullName, parentPath, token, repoObj)
        end
      end
    })

    local diag = b.create()
    diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    diag.show()
    aturTombolHurufKecil(diag, nil, "kembali", nil)
  end)
end

-- 5. Menu Aksi untuk Berkas Spesifik
menuAksiFile = function(fullName, fileData, token, currentPath, repoObj)
  local opsiFile = {
    "1. Salin tautan raw (unduh langsung / script updater)",
    "2. Edit isi berkas ini",
    "3. Salin tautan halaman web",
    "4. Bagikan tautan raw",
    "5. Hapus berkas ini"
  }

  local b = AlertDialog.Builder(service)
  b.setTitle("Kelola berkas: " .. fileData.name)
  b.setItems(opsiFile, DialogInterface.OnClickListener{
    onClick = function(dialog, which)
      if which == 0 then
        salinKeClipboard("Tautan raw", fileData.download_url)
      elseif which == 1 then
        local endpoint = "https://api.github.com/repos/" .. fullName .. "/contents/" .. fileData.path
        kirimPermintaanGitHub("GET", endpoint, token, nil, function(ok, res)
          if ok then
            local obj = JSONObject(res)
            local sha = obj.optString("sha", "")
            local base64Content = obj.optString("content", ""):gsub("%s+", "")
            local bytes = Base64.decode(base64Content, Base64.DEFAULT)
            local isiTeks = String(bytes, "UTF-8")
            
            formEditIsiBerkas(fullName, fileData.path, sha, isiTeks, token, function()
              bukaDirektoriRepoDialog(fullName, currentPath, token, repoObj)
            end, function()
              menuAksiFile(fullName, fileData, token, currentPath, repoObj)
            end)
          else
            Toast.makeText(service, "Gagal mengambil isi berkas: " .. tostring(res), Toast.LENGTH_LONG).show()
          end
        end)
      elseif which == 2 then
        salinKeClipboard("Tautan web berkas", fileData.html_url)
      elseif which == 3 then
        bagikanTautan("Tautan berkas raw: " .. fileData.name, fileData.download_url)
      elseif which == 4 then
        local konfirm = AlertDialog.Builder(service)
        konfirm.setTitle("Hapus berkas?")
        konfirm.setMessage("Apakah Anda yakin ingin menghapus berkas " .. fileData.name .. " dari repositori?")
        konfirm.setPositiveButton("hapus berkas", DialogInterface.OnClickListener{
          onClick = function()
            local delEndpoint = "https://api.github.com/repos/" .. fullName .. "/contents/" .. fileData.path
            local delPayload = JSONObject()
            delPayload.put("message", "Menghapus berkas " .. fileData.name .. " via Aksesibilitas Android")
            delPayload.put("sha", fileData.sha)

            kirimPermintaanGitHub("DELETE", delEndpoint, token, delPayload.toString(), function(sukses, hasilDel)
              if sukses then
                if service.speak then service.speak("Berkas berhasil dihapus.") end
                Toast.makeText(service, "Berkas berhasil dihapus!", Toast.LENGTH_SHORT).show()
                bukaDirektoriRepoDialog(fullName, currentPath, token, repoObj)
              else
                Toast.makeText(service, "Gagal menghapus: " .. tostring(hasilDel), Toast.LENGTH_LONG).show()
              end
            end)
          end
        })
        konfirm.setNegativeButton("kembali", DialogInterface.OnClickListener{
          onClick = function()
            menuAksiFile(fullName, fileData, token, currentPath, repoObj)
          end
        })
        local dKonfirm = konfirm.create()
        dKonfirm.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
        dKonfirm.show()
        aturTombolHurufKecil(dKonfirm, "hapus berkas", "kembali", nil)
      end
    end
  })
  b.setNegativeButton("kembali", DialogInterface.OnClickListener{
    onClick = function()
      bukaDirektoriRepoDialog(fullName, currentPath, token, repoObj)
    end
  })
  local diag = b.create()
  diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
  diag.show()
  aturTombolHurufKecil(diag, nil, "kembali", nil)
end

-- 6. Editor Teks Berkas
formEditIsiBerkas = function(repo, path, sha, isiAwal, token, onSuccess, onBatal)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(40, 20, 40, 10)

  local editor = EditText(service)
  editor.setText(isiAwal)
  editor.setMinLines(6)
  layout.addView(editor)

  local scroll = ScrollView(service)
  scroll.setFillViewport(true)
  scroll.addView(layout)

  local editBuilder = AlertDialog.Builder(service)
  editBuilder.setTitle("Edit isi: " .. path)
  editBuilder.setView(scroll)
  editBuilder.setPositiveButton("simpan perubahan", DialogInterface.OnClickListener{
    onClick = function()
      local isiBaru = tostring(editor.getText())
      local encoded = Base64.encodeToString(String(isiBaru).getBytes("UTF-8"), Base64.NO_WRAP)

      local endpoint = "https://api.github.com/repos/" .. repo .. "/contents/" .. path
      local putPayload = JSONObject()
      putPayload.put("message", "Pembaruan isi " .. path .. " via Android")
      putPayload.put("content", encoded)
      putPayload.put("sha", sha)

      kirimPermintaanGitHub("PUT", endpoint, token, putPayload.toString(), function(sukses, hasil)
        if sukses then
          if service.speak then service.speak("Perubahan berkas berhasil disimpan ke GitHub.") end
          Toast.makeText(service, "Berkas berhasil diperbarui!", Toast.LENGTH_SHORT).show()
          if onSuccess then onSuccess() end
        else
          Toast.makeText(service, "Gagal simpan: " .. tostring(hasil), Toast.LENGTH_LONG).show()
        end
      end)
    end
  })
  editBuilder.setNegativeButton("kembali", DialogInterface.OnClickListener{
    onClick = function()
      if onBatal then
        onBatal()
      else
        menuUtama()
      end
    end
  })

  local editDialog = editBuilder.create()
  editDialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
  editDialog.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
  editDialog.show()
  aturTombolHurufKecil(editDialog, "simpan perubahan", "kembali", nil)
end

-- ==========================================================
-- PEMBUATAN REPOSITORI & PENAMBAHAN BERKAS
-- ==========================================================

-- Dialog Buat Repositori Baru
buatRepoDialog = function(token)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(40, 20, 40, 10)

  local lblNama = TextView(service)
  lblNama.setText("Nama repositori (tanpa spasi):")
  layout.addView(lblNama)

  local inputNama = EditText(service)
  inputNama.setHint("contoh: plugin-baru")
  inputNama.setSingleLine(true)
  layout.addView(inputNama)

  local lblDesc = TextView(service)
  lblDesc.setText("Deskripsi repositori:")
  lblDesc.setPadding(0, 15, 0, 0)
  layout.addView(lblDesc)

  local inputDesc = EditText(service)
  inputDesc.setHint("Deskripsi proyek")
  inputDesc.setSingleLine(true)
  layout.addView(inputDesc)

  local chkPrivate = CheckBox(service)
  chkPrivate.setText("Jadikan repositori privat")
  layout.addView(chkPrivate)

  local scroll = ScrollView(service)
  scroll.setFillViewport(true)
  scroll.addView(layout)

  local b = AlertDialog.Builder(service)
  b.setTitle("Buat repositori baru")
  b.setView(scroll)
  b.setPositiveButton("buat repositori", DialogInterface.OnClickListener{
    onClick = function(dialog, which)
      local nama = tostring(inputNama.getText()):match("^%s*(.-)%s*$")
      local desc = tostring(inputDesc.getText()):match("^%s*(.-)%s*$")
      if nama == "" then
        if service.speak then service.speak("Nama repositori wajib diisi.") end
        return
      end

      local payload = JSONObject()
      payload.put("name", nama)
      payload.put("description", desc)
      payload.put("private", chkPrivate.isChecked())
      payload.put("auto_init", true)

      kirimPermintaanGitHub("POST", "https://api.github.com/user/repos", token, payload.toString(), function(ok, res)
        if ok then
          local obj = JSONObject(res)
          local htmlUrl = obj.optString("html_url", "")
          local d = AlertDialog.Builder(service)
          d.setTitle("Repositori berhasil dibuat")
          d.setMessage("Nama: " .. obj.optString("name", "") .. "\n\nTautan repositori:\n" .. htmlUrl)
          d.setPositiveButton("salin tautan", DialogInterface.OnClickListener{
            onClick = function() salinKeClipboard("Tautan repositori", htmlUrl) end
          })
          d.setNeutralButton("bagikan", DialogInterface.OnClickListener{
            onClick = function() bagikanTautan("Tautan repositori GitHub", htmlUrl) end
          })
          d.setNegativeButton("kembali", DialogInterface.OnClickListener{
            onClick = function() menuUtama() end
          })
          local diag = d.create()
          diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
          diag.show()
          aturTombolHurufKecil(diag, "salin tautan", "kembali", "bagikan")
        else
          if service.speak then service.speak("Gagal membuat repositori: " .. tostring(res)) end
          Toast.makeText(service, tostring(res), Toast.LENGTH_LONG).show()
        end
      end)
    end
  })
  b.setNegativeButton("kembali", DialogInterface.OnClickListener{
    onClick = function()
      menuUtama()
    end
  })

  local diag = b.create()
  diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
  diag.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
  diag.show()
  aturTombolHurufKecil(diag, "buat repositori", "kembali", nil)
end

-- Dialog Menambah Berkas Baru
tambahFileRepoDialog = function(token, repoOtomatis, repoObj)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(40, 20, 40, 10)

  local lblRepo = TextView(service)
  lblRepo.setText("Nama repositori:")
  layout.addView(lblRepo)

  local inputRepo = EditText(service)
  inputRepo.setHint("contoh: username/nama-repo")
  inputRepo.setSingleLine(true)
  if repoOtomatis then
    inputRepo.setText(repoOtomatis)
  end
  layout.addView(inputRepo)

  local lblPath = TextView(service)
  lblPath.setText("Nama berkas:")
  lblPath.setPadding(0, 15, 0, 0)
  layout.addView(lblPath)

  local inputPath = EditText(service)
  inputPath.setHint("contoh: main.lua atau data.txt")
  inputPath.setSingleLine(true)
  layout.addView(inputPath)

  local lblKonten = TextView(service)
  lblKonten.setText("Isi berkas:")
  lblKonten.setPadding(0, 15, 0, 0)
  layout.addView(lblKonten)

  local inputKonten = EditText(service)
  inputKonten.setHint("Ketik atau tempel isi berkas di sini...")
  inputKonten.setMinLines(5)
  layout.addView(inputKonten)

  local scroll = ScrollView(service)
  scroll.setFillViewport(true)
  scroll.addView(layout)

  local b = AlertDialog.Builder(service)
  b.setTitle("Tambah berkas baru")
  b.setView(scroll)
  b.setPositiveButton("simpan berkas", DialogInterface.OnClickListener{
    onClick = function(dialog, which)
      local repo = tostring(inputRepo.getText()):match("^%s*(.-)%s*$")
      local path = tostring(inputPath.getText()):match("^%s*(.-)%s*$")
      local konten = tostring(inputKonten.getText())

      if repo == "" or path == "" then
        Toast.makeText(service, "Nama repo dan nama berkas wajib diisi!", Toast.LENGTH_SHORT).show()
        return
      end

      local kontenBase64 = Base64.encodeToString(String(konten).getBytes("UTF-8"), Base64.NO_WRAP)
      local payload = JSONObject()
      payload.put("message", "Menambahkan berkas " .. path)
      payload.put("content", kontenBase64)

      local endpoint = "https://api.github.com/repos/" .. repo .. "/contents/" .. path
      kirimPermintaanGitHub("PUT", endpoint, token, payload.toString(), function(ok, res)
        if ok then
          local obj = JSONObject(res)
          local contentObj = obj.optJSONObject("content")
          local fileUrl = contentObj and contentObj.optString("html_url", "") or ""
          local rawUrl = contentObj and contentObj.optString("download_url", "") or ""
          
          local d = AlertDialog.Builder(service)
          d.setTitle("Berkas berhasil ditambahkan")
          d.setMessage("Berkas: " .. path .. "\n\nTautan raw (updater):\n" .. rawUrl .. "\n\nTautan halaman:\n" .. fileUrl)
          d.setPositiveButton("salin tautan raw", DialogInterface.OnClickListener{
            onClick = function() salinKeClipboard("Tautan raw updater", rawUrl) end
          })
          d.setNeutralButton("bagikan", DialogInterface.OnClickListener{
            onClick = function() bagikanTautan("Tautan berkas: " .. path, rawUrl) end
          })
          d.setNegativeButton("kembali", DialogInterface.OnClickListener{
            onClick = function()
              if repoObj then
                kelolaRepoPilihanDialog(repoObj, token)
              else
                menuUtama()
              end
            end
          })
          local diag = d.create()
          diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
          diag.show()
          aturTombolHurufKecil(diag, "salin tautan raw", "kembali", "bagikan")
        else
          Toast.makeText(service, "Gagal: " .. tostring(res), Toast.LENGTH_LONG).show()
        end
      end)
    end
  })
  b.setNegativeButton("kembali", DialogInterface.OnClickListener{
    onClick = function()
      if repoObj then
        kelolaRepoPilihanDialog(repoObj, token)
      else
        menuUtama()
      end
    end
  })

  local diag = b.create()
  diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
  diag.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
  diag.show()
  aturTombolHurufKecil(diag, "simpan berkas", "kembali", nil)
end

-- ==========================================================
-- MENU UTAMA & PENYIMPANAN TOKEN
-- ==========================================================

menuUtama = function()
  local token = prefs.getString(KEY_TOKEN, "")
  if token == "" then
    tampilkanDialogLogin()
    return
  end

  local menuItems = {
    "1. Daftar dan kelola repositori saya (buka repo, berkas & tautan)",
    "2. Buat repositori baru",
    "3. Buka halaman buat token di web",
    "4. Ganti akun / keluar (hapus token)"
  }

  local b = AlertDialog.Builder(service)
  b.setTitle("Pengelola GitHub pribadi")
  b.setItems(menuItems, DialogInterface.OnClickListener{
    onClick = function(dialog, which)
      if which == 0 then
        daftarRepoSayaDialog(token)
      elseif which == 1 then
        buatRepoDialog(token)
      elseif which == 2 then
        bukaBrowser(URL_GENERATE_TOKEN)
      elseif which == 3 then
        prefs.edit().remove(KEY_TOKEN).apply()
        if service.speak then service.speak("Token dihapus. Anda telah keluar.") end
        Toast.makeText(service, "Token dihapus dari perangkat.", Toast.LENGTH_SHORT).show()
      end
    end
  })
  b.setNegativeButton("tutup", nil)
  local diag = b.create()
  diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
  diag.show()
  aturTombolHurufKecil(diag, nil, "tutup", nil)
end

tampilkanDialogLogin = function()
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(40, 20, 40, 10)

  local input = EditText(service)
  input.setHint("Tempel token GitHub di sini")
  input.setSingleLine(true)
  layout.addView(input)

  local scroll = ScrollView(service)
  scroll.setFillViewport(true)
  scroll.addView(layout)

  local b = AlertDialog.Builder(service)
  b.setTitle("Masuk akun GitHub")
  b.setMessage("Masukkan personal access token Anda. Jika belum memiliki token, tekan tombol 'Dapatkan token di web' di bawah:")
  b.setView(scroll)

  b.setPositiveButton("simpan token", DialogInterface.OnClickListener{
    onClick = function()
      local t = tostring(input.getText()):match("^%s*(.-)%s*$")
      if t == "" then
        Toast.makeText(service, "Token tidak boleh kosong!", Toast.LENGTH_SHORT).show()
        return
      end
      prefs.edit().putString(KEY_TOKEN, t).apply()
      if service.speak then service.speak("Token berhasil disimpan.") end
      menuUtama()
    end
  })

  b.setNeutralButton("dapatkan token di web", DialogInterface.OnClickListener{
    onClick = function()
      bukaBrowser(URL_GENERATE_TOKEN)
    end
  })

  b.setNegativeButton("tutup", nil)

  local diag = b.create()
  diag.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
  diag.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
  diag.show()
  aturTombolHurufKecil(diag, "simpan token", "tutup", "dapatkan token di web")
end

menuUtama()
