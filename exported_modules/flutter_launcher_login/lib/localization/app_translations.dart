/// Sistema de traducciones multi-idioma
/// 
/// Soporta: Inglés (en), Español (es), Coreano (ko)
/// 
/// Uso:
/// ```dart
/// final provider = LanguageProvider();
/// provider.setLocale('es');
/// print(provider.tr('login_title')); // "Iniciar Sesión"
/// ```
class LanguageProvider {
  String _currentLocale = 'en';
  
  String get currentLocale => _currentLocale;
  
  void setLocale(String locale) {
    if (_translations.containsKey(locale)) {
      _currentLocale = locale;
    }
  }
  
  String tr(String key) {
    return _translations[_currentLocale]?[key] ?? 
           _translations['en']?[key] ?? 
           key;
  }
  
  static final Map<String, Map<String, String>> _translations = {
    'en': {
      // Login
      'login_title': 'Login',
      'login_subtitle': 'Enter your credentials',
      'login_username': 'Username',
      'login_password': 'Password',
      'login_button': 'Sign In',
      'login_empty_fields': 'Please enter username and password',
      'login_attempts_remaining': 'Attempts remaining',
      'login_error': 'Authentication error',
      'login_success': 'Login successful',
      
      // General
      'system_name': 'Control System',
      'loading': 'Loading...',
      'error': 'Error',
      'success': 'Success',
      'cancel': 'Cancel',
      'confirm': 'Confirm',
      'save': 'Save',
      'delete': 'Delete',
      'edit': 'Edit',
      'add': 'Add',
      'search': 'Search',
      'filter': 'Filter',
      'refresh': 'Refresh',
      'close': 'Close',
      'yes': 'Yes',
      'no': 'No',
      
      // Status
      'connecting': 'Connecting...',
      'server_ready': 'Server ready!',
      'server_error': 'Server error',
      'connection_error': 'Connection error',
    },
    
    'es': {
      // Login
      'login_title': 'Iniciar Sesión',
      'login_subtitle': 'Ingrese sus credenciales',
      'login_username': 'Usuario',
      'login_password': 'Contraseña',
      'login_button': 'Entrar',
      'login_empty_fields': 'Por favor ingrese usuario y contraseña',
      'login_attempts_remaining': 'Intentos restantes',
      'login_error': 'Error de autenticación',
      'login_success': 'Inicio de sesión exitoso',
      
      // General
      'system_name': 'Sistema de Control',
      'loading': 'Cargando...',
      'error': 'Error',
      'success': 'Éxito',
      'cancel': 'Cancelar',
      'confirm': 'Confirmar',
      'save': 'Guardar',
      'delete': 'Eliminar',
      'edit': 'Editar',
      'add': 'Agregar',
      'search': 'Buscar',
      'filter': 'Filtrar',
      'refresh': 'Actualizar',
      'close': 'Cerrar',
      'yes': 'Sí',
      'no': 'No',
      
      // Status
      'connecting': 'Conectando...',
      'server_ready': '¡Servidor listo!',
      'server_error': 'Error del servidor',
      'connection_error': 'Error de conexión',
    },
    
    'ko': {
      // Login
      'login_title': '로그인',
      'login_subtitle': '자격 증명을 입력하세요',
      'login_username': '사용자명',
      'login_password': '비밀번호',
      'login_button': '로그인',
      'login_empty_fields': '사용자명과 비밀번호를 입력하세요',
      'login_attempts_remaining': '남은 시도 횟수',
      'login_error': '인증 오류',
      'login_success': '로그인 성공',
      
      // General
      'system_name': '제어 시스템',
      'loading': '로딩 중...',
      'error': '오류',
      'success': '성공',
      'cancel': '취소',
      'confirm': '확인',
      'save': '저장',
      'delete': '삭제',
      'edit': '편집',
      'add': '추가',
      'search': '검색',
      'filter': '필터',
      'refresh': '새로고침',
      'close': '닫기',
      'yes': '예',
      'no': '아니오',
      
      // Status
      'connecting': '연결 중...',
      'server_ready': '서버 준비 완료!',
      'server_error': '서버 오류',
      'connection_error': '연결 오류',
    },
  };
  
  /// Agrega o actualiza traducciones
  static void addTranslations(String locale, Map<String, String> translations) {
    if (_translations.containsKey(locale)) {
      _translations[locale]!.addAll(translations);
    } else {
      _translations[locale] = translations;
    }
  }
  
  /// Lista de idiomas disponibles
  static List<String> get availableLocales => _translations.keys.toList();
}
