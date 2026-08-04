'use strict';

const service = require('../services/solderPasteLifecycleService');

function actorFromBody(body = {}) {
  return {
    usuario: String(body.usuario || body.username || 'Sistema').trim() || 'Sistema',
    usuarioId: body.usuario_id || body.user_id || null,
  };
}

exports.scan = async (req, res, next) => {
  try {
    const actor = actorFromBody(req.body);
    const process = await service.scanMaterial({
      code: req.body?.code,
      usuario: actor.usuario,
      usuarioId: actor.usuarioId,
      enforceFifo: req.body?.enforce_fifo !== false,
    });
    res.json({
      success: true,
      process,
    });
  } catch (error) {
    next(error);
  }
};

exports.getAll = async (req, res, next) => {
  try {
    const processes = await service.listProcesses({
      status: req.query.status,
      search: req.query.search,
      limit: req.query.limit,
    });
    res.json({ success: true, processes });
  } catch (error) {
    next(error);
  }
};

exports.getEvents = async (req, res, next) => {
  try {
    const events = await service.listEvents({
      afterId: req.query.after_id,
      limit: req.query.limit,
    });
    res.json({ success: true, events });
  } catch (error) {
    next(error);
  }
};

exports.getStatus = async (req, res, next) => {
  try {
    const result = await service.getStatusByCode(req.params.code);
    res.json({ success: true, ...result });
  } catch (error) {
    next(error);
  }
};

exports.startAgitation = async (req, res, next) => {
  try {
    const process = await service.startAgitation({
      processId: req.params.id,
      usuario: actorFromBody(req.body).usuario,
    });
    res.json({ success: true, process });
  } catch (error) {
    next(error);
  }
};

exports.assignLine = async (req, res, next) => {
  try {
    const process = await service.assignLine({
      processId: req.params.id,
      line: req.body?.line,
      usuario: actorFromBody(req.body).usuario,
    });
    res.json({ success: true, process });
  } catch (error) {
    next(error);
  }
};

exports.consume = async (req, res, next) => {
  try {
    const process = await service.consume({
      processId: req.params.id,
      usuario: actorFromBody(req.body).usuario,
    });
    res.json({ success: true, process });
  } catch (error) {
    next(error);
  }
};

exports.returnToCold = async (req, res, next) => {
  try {
    const actor = actorFromBody(req.body);
    const process = await service.returnToCold({
      processId: req.params.id,
      usuario: actor.usuario,
      usuarioId: actor.usuarioId,
    });
    res.json({ success: true, process });
  } catch (error) {
    next(error);
  }
};

exports.cancel = async (req, res, next) => {
  try {
    const process = await service.cancel({
      processId: req.params.id,
      usuario: actorFromBody(req.body).usuario,
    });
    res.json({ success: true, process });
  } catch (error) {
    next(error);
  }
};
