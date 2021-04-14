#!/bin/bash

set -e

TARGET='font-config'

#### Functions =================================================================

showmessage()
{
    local message="$1"

    if tty -s
    then
        echo "${message}"
        read -p "Press [Enter] to continue"
    else
        zenity --info --width 400 --text="${message}"
    fi
}

showquestion()
{
    local message="$1"

    if tty -s
    then
        while true
        do
            read -p "${message} [Y/n] " RESULT

            if [[ -z "${RESULT}" || "${RESULT,,}" == 'y' ]]
            then
                return 0
            fi

            if [[ "${RESULT,,}" == 'n' ]]
            then
                return 1
            fi
        done
    else
        if zenity --question --width 400 --text="${message}"
        then
            return 0
        else
            return 1
        fi
    fi
}

selectvalue()
{
    local title="$1"
    local prompt="$2"
    
    shift
    shift

    local result=''

    if tty -s
    then
        result=''
        
        echo "${prompt}" >&2
        select result in "$@"
        do
            if [[ -z "${REPLY}" ]] || [[ ${REPLY} -gt 0 && ${REPLY} -le $# ]]
            then
                break
            else
                
                continue
            fi
        done
    else
        while true
        do
            result=$(zenity --title="$title" --text="$prompt" --list --column="Options" "$@") || break
            if [[ -n "$result" ]]
            then
                break
            fi
        done
    fi
    
    echo "$result"
}

disableautostart()
{
    showmessage "Configuration completed. You can re-configure monospace font by running '${TARGET}' command"

    mkdir -p "${HOME}/.config/${TARGET}"
    echo "autostart=false" > "${HOME}/.config/${TARGET}/setup-done"
}

function ispkginstalled()
{
    app="$1"

    if dpkg -s "${app}" >/dev/null 2>&1
    then
        return 0
    else
        return 1
    fi
}

getscale()
{
    local defaultdpi=96
    local sizepx="$1"
    local sizemm="$2"
    
    if [[ $sizepx -le 0 ]] || [[ $sizemm -le 0 ]]
    then
        return 1
    fi
    
    local dpi="$(echo "${sizepx} / (${sizemm} / 25.4)" | bc -l)"
    local scalelong="$(echo "${dpi} / 96" | bc -l)"
    local scale="$(LC_NUMERIC=C printf "%.2f" "${scalelong}" | sed '/\./ s/\.\{0,1\}0\{1,\}$//')"
    
    if [[ -z "$scale" || "$scale" == '0' ]]
    then
        return 1
    fi
    
    echo "${scale}"
}

roundscale()
{
    LC_NUMERIC=C printf "%.1f" "$1" | sed '/\./ s/\.\{0,1\}0\{1,\}$//'
}

roundfloat()
{
    LC_NUMERIC=C printf "%.0f" "$1" | sed '/\./ s/\.\{0,1\}0\{1,\}$//'
}

safestring()
{
    local inputstr="$1"

    echo "${inputstr}" | sed 's/\\/\\\\/g;s/\//\\\//g'
}

getconfigline()
{
    local key="$1"
    local section="$2"
    local file="$3"

    if [[ -r "$file" ]]
    then
        sed -n "/^[ \t]*\[$(safestring "${section}")\]/,/\[/s/^[ \t]*$(safestring "${key}")[ \t]*=[ \t]*//p" "${file}"
    fi
}

addconfigline()
{
    local key="$1"
    local value="$2"
    local section="$3"
    local file="$4"

    if ! grep -F "[${section}]" "$file" 1>/dev/null 2>/dev/null
    then
        mkdir -p "$(dirname "$file")"

        echo >> "$file"

        echo "[${section}]" >> "$file"
    fi

    sed -i "/^[[:space:]]*\[${section}\][[:space:]]*$/,/^[[:space:]]*\[.*/{/^[[:space:]]*$(safestring "${key}")[[:space:]]*=/d}" "$file"

    sed -i "/\[${section}\]/a $(safestring "${key}=${value}")" "$file"

    if [[ -n "$(tail -c1 "${file}")" ]]
    then
        echo >> "${file}"
    fi
}

backup_file()
{
    local file="$1"
    
    [[ -f "${file}" ]] && cp -f "${file}" "${file}.old"
}

restore_file()
{
    local file="$1"

    if [[ -f "${file}.old" ]]
    then
        mv "${file}.old" "${file}"
    else
        rm -f "${file}"
    fi
}

restore_schema()
{
    local schema="$1"
    local oldvalue="$2"
    
    if gsettings writable $schema 1>/dev/null 2>/dev/null
    then
        if [[ -n "${oldvalue}" ]]
        then
            gsettings set $schema "${oldvalue}"
        else
            gsettings reset $schema
        fi
    fi
}

#### Globals ===================================================================

unset faces_list
declare -a faces_list

unset sizes_list
declare -a sizes_list

unset scale_list
declare -a scale_list

faces_list=('Ubuntu Mono' 'Fira Code' 'JetBrains Mono' 'Noto Sans Mono' 'Hack' 'Consolas')
sizes_list=('10' '12' '14' '16' '18')
scale_list=('1.0' '1.15' '1.2' '1.25' '1.3' '1.4' '1.5' '1.75' '2.0')

#### Get system monospace fonts ================================================

# TODO

#### Get displays DPI list =====================================================

while read -r displayinfo
do
    sizepx="$(echo "${displayinfo}" | grep -o '[[:digit:]]\+x[[:digit:]]\+')"
    sizespx=("${sizepx%%x*}" "${sizepx##*x}")

    sizemm=$(echo "${displayinfo}" | grep -o '[[:digit:]]\+mm' | sed 's/mm$//' | tr '\n' 'x' | sed 's/x$//')
    sizesmm=("${sizemm%%x*}" "${sizemm##*x}")

    for i in 0 1
    do
        scale="$(getscale "${sizespx[$i]}" "${sizesmm[$i]}")"
        
        scale_list+=("$scale")
        scale_list+=("$(roundscale "$scale")")
    done
done < <(LC_ALL=C xrandr | grep ' connected')

#### Sort and remove duplicates from lists =====================================

readarray -t faces < <(for a in "${faces_list[@]}"; do echo "$a"; done | uniq)
readarray -t sizes < <(for a in "${sizes_list[@]}"; do echo "$a"; done | sort -g | uniq)
readarray -t scale < <(for a in "${scale_list[@]}"; do echo "$a"; done | sort -g | uniq)

#### Settings shemas and configuration files ===================================

readonly font_schema_gnome="org.gnome.desktop.interface monospace-font-name"
readonly font_file_kde="${HOME}/.config/kdeglobals"
readonly font_schema_builder="org.gnome.builder.editor font-name"
readonly font_file_qtcreator="${HOME}/.config/QtProject/QtCreator.ini"
readonly font_file_konsole="${HOME}/.local/share/konsole/UTF-8.profile"
readonly font_file_kate="${HOME}/.config/kateschemarc"
readonly font_file_sqlitebrowser="${HOME}/.config/sqlitebrowser/sqlitebrowser.conf"
readonly font_file_ghostwriter="${HOME}/.config/ghostwriter/ghostwriter.conf"

readonly scale_schema_gnome="org.gnome.desktop.interface text-scaling-factor"
readonly scale_schema_cinnamon="org.cinnamon.desktop.interface text-scaling-factor"
readonly scale_schema_dashpanel="org.gnome.shell.extensions.dash-to-dock dash-max-icon-size"
readonly scale_schema_epiphany="/org/gnome/epiphany/web/default-zoom-level"
readonly scale_schema_libreoffice="/oor:items/item[@oor:path='/org.openoffice.Office.Common/Misc']/prop[@oor:name='SymbolStyle']/value"
readonly scale_file_libreoffice="${HOME}/.config/libreoffice/4/user/registrymodifications.xcu"
readonly scale_schema_marker="com.github.fabiocolacio.marker.preferences.preview preview-zoom-level"

while true
do
    ### Select new settings ====================================================

    newfont="$(selectvalue 'Monospace font' 'Please select font:' "${faces[@]}")"
    
    if [[ -n "$newfont" ]]
    then
        newsize="$(selectvalue 'Font size' 'Please select size:' "${sizes[@]}")"
    fi
    
    if [[ -n "$newfont" && -n "$newsize" ]]
    then
        newscale="$(selectvalue 'Text scaling factor' 'Please select text scaling factor:' "${scale[@]}")"
    fi
    
    newoptionskde="-1,5,50,0,0,0,0,0"
    newtypekde="Regular"
    
    ### Apply new settings =====================================================
    
    if [[ -n "$newfont" && -n "$newsize" && -n "$newscale" ]]
    then
    
        ## Gnome/Cinnamon ------------------------------------------------------
        
        if gsettings writable $font_schema_gnome 1>/dev/null 2>/dev/null
        then
            oldfontgnome="$(gsettings get $font_schema_gnome)"
            gsettings set $font_schema_gnome "${newfont} ${newsize}"
        fi
        
        if gsettings writable $scale_schema_gnome 1>/dev/null 2>/dev/null
        then
            oldscalegnome="$(gsettings get $scale_schema_gnome)"
            gsettings set $scale_schema_gnome ${newscale}
        fi
        
        if gsettings writable $scale_schema_cinnamon 1>/dev/null 2>/dev/null
        then
            oldscalecinnamon="$(gsettings get $scale_schema_cinnamon)"
            gsettings set $scale_schema_cinnamon ${newscale}
        fi
        
        ## KDE -----------------------------------------------------------------
        
        if [[ -f "$font_file_kde" ]]
        then
            backup_file "$font_file_kde"
            
            addconfigline 'fixed' "${newfont},${newsize},${newoptionskde},${newtypekde}" 'General' "$font_file_kde"
        fi
        
        ## Dash panel ----------------------------------------------------------
        
        if gsettings writable $scale_schema_dashpanel 1>/dev/null 2>/dev/null
        then
            iconsize="$(roundfloat "$(echo "48 * ${newscale}" | bc -l)")"
            oldsizedashpanel="$(gsettings get $scale_schema_dashpanel)"
            gsettings set $scale_schema_dashpanel ${iconsize}
        fi
        
        ## Epiphany browser ----------------------------------------------------
        
        if ispkginstalled epiphany-browser && ispkginstalled dconf-cli
        then
            oldscaleepiphany="$(dconf read $scale_schema_epiphany)"
            dconf write $scale_schema_epiphany ${newscale}
        fi
        
        ## Libre Office --------------------------------------------------------
        
        if [[ -f "$scale_file_libreoffice" ]]
        then
            if [[ $(echo "$newscale > 1.26" | bc -l) -eq 0 ]]
            then
                loicontheme=breeze
            else
                loicontheme=breeze_svg
            fi
            
            backup_file "$scale_file_libreoffice"
        
            xmlstarlet edit --inplace --update "$scale_schema_libreoffice" --value "$loicontheme" "$scale_file_libreoffice"
        fi
        
        ## Gnome Builder -------------------------------------------------------
        
        if gsettings writable $font_schema_builder 1>/dev/null 2>/dev/null
        then
            oldfontbuilder="$(gsettings get $font_schema_builder)"
            gsettings set $font_schema_builder "${newfont} ${newsize}"
        fi
        
        ## Qt Creator ----------------------------------------------------------
        
        if ispkginstalled qtcreator
        then
            backup_file "$font_file_qtcreator"
            
            addconfigline 'FontFamily' "${newfont}" 'TextEditor' "$font_file_qtcreator"
            addconfigline 'FontSize'   "${newsize}" 'TextEditor' "$font_file_qtcreator"
        fi
        
        ## Konsole -------------------------------------------------------------
        
        if ispkginstalled konsole
        then
            backup_file "$font_file_konsole"
            
            addconfigline 'Font' "${newfont},${newsize},${newoptionskde},${newtypekde}" 'Appearance' "$font_file_konsole"
        fi
        
        ## Kate ----------------------------------------------------------------
        
        if ispkginstalled kate
        then
            backup_file "$font_file_kate"
            
            addconfigline 'Font' "${newfont},${newsize},${newoptionskde},${newtypekde}" 'Normal' "$font_file_kate"
        fi
        
        ## SQLite Browser ------------------------------------------------------
        
        if ispkginstalled sqlitebrowser
        then
            backup_file "$font_file_sqlitebrowser"
            
            addconfigline 'font'     "${newfont}" 'editor'      "$font_file_sqlitebrowser"
            addconfigline 'fontsize' "${newsize}" 'editor'      "$font_file_sqlitebrowser"
            addconfigline 'font'     "${newfont}" 'databrowser' "$font_file_sqlitebrowser"
        fi
        
        ## Ghostwriter ---------------------------------------------------------
        
        if ispkginstalled ghostwriter
        then
            backup_file "$font_file_ghostwriter"
            
            addconfigline 'font' "${newfont},${newsize},${newoptionskde}" 'Style' "$font_file_ghostwriter"
        fi
        
        ## Marker --------------------------------------------------------------
        
        if ispkginstalled marker
        then
            oldscalemarker="$(gsettings get $scale_schema_marker)"
            gsettings set $scale_schema_marker ${newscale}
        fi
        
        ## ---------------------------------------------------------------------
        
        if showquestion "Save these settings?" "save" "try another"
        then
            break
        else
        
            ### Reset settings =================================================
            
            ## Gnome/Cinnamon --------------------------------------------------
            
            restore_schema "$font_schema_gnome" "${oldfontgnome}"
            restore_schema "$scale_schema_gnome" "${oldscalegnome}"
            restore_schema "$scale_schema_cinnamon" "${oldscalecinnamon}"
            
            ## KDE -------------------------------------------------------------
            
            restore_file "$font_file_kde"
            
            ## Dash panel ------------------------------------------------------
            
            restore_schema "$scale_schema_dashpanel" "${oldsizedashpanel}"
            
            ## Epiphany browser ------------------------------------------------
            
            if ispkginstalled epiphany-browser && ispkginstalled dconf-cli
            then
                if [[ -n "${oldscaleepiphany}" ]]
                then
                    dconf write $scale_schema_epiphany ${oldscaleepiphany}
                else
                    dconf reset $scale_schema_epiphany
                fi
            fi
            
            ## Libre Office ----------------------------------------------------
            
            restore_file "$scale_file_libreoffice"
            
            ## Gnome Builder ---------------------------------------------------
            
            restore_schema "$font_schema_builder" "${oldfontbuilder}"
            
            ## Qt Creator ------------------------------------------------------
            
            restore_file "$font_file_qtcreator"
            
            ## Konsole ---------------------------------------------------------
            
            restore_file "$font_file_konsole"
            
            ## Kate ------------------------------------------------------------
            
            restore_file "$font_file_kate"
            
            ## SQLite Browser --------------------------------------------------
            
            restore_file "$font_file_sqlitebrowser"
            
            ## Ghostwriter -----------------------------------------------------
            
            restore_file "$font_file_ghostwriter"
            
            ## Marker ----------------------------------------------------------
            
            restore_schema "$scale_schema_marker" "${oldscalemarker}"
            
            ## -----------------------------------------------------------------
            
            continue
        fi
    fi
    
    break

done

#### Disable autostart =========================================================

disableautostart
