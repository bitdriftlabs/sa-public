import React from 'react';
import {View, Text, StyleSheet, TouchableOpacity, ActivityIndicator} from 'react-native';
import {useSimulation} from '../context/SimulationContext';
import {Colors} from '../utils/colors';

export const SimulationOverlay: React.FC = () => {
  const {isSimulating, currentRun, totalRuns, isInfinite, cancelSimulation} =
    useSimulation();

  if (!isSimulating) {
    return null;
  }

  const progressText = isInfinite
    ? `Run ${currentRun} / ∞`
    : `Run ${currentRun} / ${totalRuns}`;

  return (
    <View style={styles.container}>
      <View style={styles.card}>
        <ActivityIndicator size="small" color={Colors.white} style={styles.spinner} />
        <Text style={styles.text}>{progressText}</Text>
        <TouchableOpacity onPress={cancelSimulation} style={styles.cancelButton}>
          <Text style={styles.cancelText}>X</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    bottom: 40,
    left: 0,
    right: 0,
    alignItems: 'center',
    zIndex: 1000,
  },
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(0, 0, 0, 0.78)',
    borderRadius: 12,
    paddingVertical: 10,
    paddingHorizontal: 14,
    shadowColor: Colors.black,
    shadowOffset: {width: 0, height: 2},
    shadowOpacity: 0.35,
    shadowRadius: 10,
    elevation: 10,
  },
  spinner: {
    marginRight: 12,
  },
  text: {
    fontSize: 14,
    fontWeight: '600',
    color: Colors.white,
  },
  cancelButton: {
    marginLeft: 12,
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: 'rgba(255,255,255,0.18)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  cancelText: {
    fontSize: 11,
    color: Colors.white,
    fontWeight: '700',
  },
});
