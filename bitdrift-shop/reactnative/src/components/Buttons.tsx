import React from 'react';
import {TouchableOpacity, Text, StyleSheet, View} from 'react-native';
import {Colors} from '../utils/colors';

type ButtonProps = {
  title: string;
  icon: string;
  onPress: () => void;
  disabled?: boolean;
};

type SimButtonProps = {
  title: string;
  color: string;
  onPress: () => void;
};

export const PrimaryButton: React.FC<ButtonProps> = ({title, icon, onPress, disabled}) => (
  <TouchableOpacity
    style={[styles.primaryButton, disabled && styles.disabled]}
    onPress={onPress}
    disabled={disabled}
    activeOpacity={0.85}>
    <View style={styles.leftContent}>
      <Text style={[styles.icon, styles.primaryIcon]}>{icon}</Text>
      <Text style={styles.primaryText}>{title}</Text>
    </View>
    <Text style={styles.arrow}>›</Text>
  </TouchableOpacity>
);

export const SecondaryButton: React.FC<ButtonProps> = ({title, icon, onPress, disabled}) => (
  <TouchableOpacity
    style={[styles.secondaryButton, disabled && styles.disabled]}
    onPress={onPress}
    disabled={disabled}
    activeOpacity={0.85}>
    <View style={styles.leftContent}>
      <Text style={styles.icon}>{icon}</Text>
      <Text style={styles.secondaryText}>{title}</Text>
    </View>
    <Text style={styles.secondaryArrow}>›</Text>
  </TouchableOpacity>
);

export const SimButton: React.FC<SimButtonProps> = ({title, color, onPress}) => (
  <TouchableOpacity style={[styles.simButton, {backgroundColor: color}]} onPress={onPress} activeOpacity={0.85}>
    <Text style={styles.simText}>{title}</Text>
  </TouchableOpacity>
);

const styles = StyleSheet.create({
  primaryButton: {
    backgroundColor: Colors.text,
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 14,
    marginBottom: 10,
    borderWidth: 1,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  secondaryButton: {
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 14,
    marginBottom: 10,
    borderWidth: 1,
    borderColor: Colors.panelBorder,
    backgroundColor: Colors.panel,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  disabled: {
    opacity: 0.5,
  },
  leftContent: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
  },
  icon: {
    fontSize: 16,
    marginRight: 10,
  },
  primaryIcon: {
    color: Colors.white,
  },
  primaryText: {
    color: Colors.white,
    fontSize: 15,
    fontWeight: '700',
    flexShrink: 1,
  },
  secondaryText: {
    color: Colors.text,
    fontSize: 15,
    fontWeight: '600',
    flexShrink: 1,
  },
  arrow: {
    color: Colors.white,
    fontSize: 22,
    fontWeight: '300',
    marginLeft: 10,
  },
  secondaryArrow: {
    color: Colors.text,
    fontSize: 22,
    fontWeight: '300',
    marginLeft: 10,
  },
  simButton: {
    borderRadius: 10,
    paddingVertical: 10,
    paddingHorizontal: 10,
    minWidth: 76,
    alignItems: 'center',
    justifyContent: 'center',
  },
  simText: {
    color: Colors.white,
    fontSize: 14,
    fontWeight: '700',
  },
});
