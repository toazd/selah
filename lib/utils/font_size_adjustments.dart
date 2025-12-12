class FontSizeAdjustments {
  // Simple adjustment factors for each font so they display similar character
  // sizes at the same values shown by the UI
  // 1.0 = no adjustment (baseline)
  // 0.8 = 20% smaller, 1.2 = 20% larger
  static const Map<String, double> fontAdjustments = {
    'Arimo': 1.05,
    'Open Sans': 1.05,
    'Daddy Time Mono': 1.0,
    'Inconsolata': 1.1,
    'Roboto Mono': 1.0,
    'Gabriela': 1.0,
    'Caveat': 1.3,
    'Dancing Script': 1.3,
    'Lobster Two': 1.2,
    'Ubuntu': 1.0,
    'Liberation Sans': 1.0,
    'Tinos': 1.1,
    'Merriweather': 1.0,
    'Liberation Serif': 1.1,
    'Special Gothic': 1.05,
    'Rosemartin': 0.9,
    'Playfair Display': 1.0,
    'Morris Roman': 1.3,
    'JSL Ancient': 1.3,
    'Louis George Cafe': 1.1,
    'Comfortaa': 0.9,
    'King Sans': 1.25,
    'Fauna One': 0.9,
    'Hepta Slab': 0.9,
    'IBM Plex Sans': 1.0,
    'Libertinus Sans': 1.1,
    'Montserrat': 0.9,
    'Noto Sans': 0.95,
    'Old Standard': 1.05,
    'Sanchez': 0.95,
    'Scope One': 1.0,
    'Solway': 1.0,
  };

  // Get the adjustment factor for a font, with fallback to 1.0
  static double _getAdjustment(String fontFamily) {
    return fontAdjustments[fontFamily] ?? 1.0;
  }

  // Get the adjusted font size
  static double getAdjustedSize(String fontFamily, double baseSize) {
    return baseSize * _getAdjustment(fontFamily);
  }
}
