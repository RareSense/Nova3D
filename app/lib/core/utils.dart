String mimeTypeForExtension(String ext) => switch (ext.toLowerCase()) {
  'jpg' || 'jpeg' => 'image/jpeg',
  'webp' => 'image/webp',
  _ => 'image/png',
};
