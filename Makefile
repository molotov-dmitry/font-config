TARGET			= font-config
INSTALL_DIR  	= $(PREFIX)/usr/local/bin
AUTOSTART_DIR	= $(PREFIX)/etc/xdg/autostart

.PHONY: all install uninstall

all:

install: $(INSTALL_DIR)/$(TARGET) $(AUTOSTART_DIR)/$(TARGET).desktop

uninstall:
	rm -f $(INSTALL_DIR)/$(TARGET) $(AUTOSTART_DIR)/$(TARGET).desktop

### Executable =================================================================

$(INSTALL_DIR):
	mkdir -p $(INSTALL_DIR)

$(INSTALL_DIR)/$(TARGET): $(INSTALL_DIR) $(TARGET).sh
	install $(TARGET).sh $(INSTALL_DIR)/$(TARGET)

### Global autostart ===========================================================
	
$(AUTOSTART_DIR):
	mkdir -p $(AUTOSTART_DIR)

$(AUTOSTART_DIR)/$(TARGET).desktop: $(AUTOSTART_DIR) $(TARGET).desktop
	cp -f $(TARGET).desktop $(AUTOSTART_DIR)/$(TARGET).desktop

